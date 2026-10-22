/**

  run-nginx -- headless supervisor and configuration generator for the
  reverse-proxy image. There is no shell in the container, so everything the old
  start.sh / nginx-configure.sh did in shell is done here in C++:

    1. Render /etc/nginx from the /etc/nginx.template with environment variable
       substitution (the envwrap mechanism), so nginx can be configured at
       instantiation time -- something nginx cannot do on its own.
    2. Generate the per-virtual-host server blocks from the forward / redirect
       rules, taken from the environment variables FORWARD and REDIRECT and/or
       from the file /config/reverse-proxy.conf. Wire per-domain basic-auth.
    3. Start nginx and keep it running.
    4. Watch the certificates in /etc/letsencrypt/live and the configuration in
       /config; on any change, regenerate and reload nginx gracefully.
    5. Forward termination signals to nginx for a clean shutdown (PID 1 duty).

  Configuration format (the `--` prefix of the old parameter form is dropped):

    FORWARD / REDIRECT environment variables, one rule per line:
        <source> <target>

    /config/reverse-proxy.conf, one rule per line, verb as first word:
        forward   <source> <target>
        redirect  <source> <target>

  Environment and file are merged; on a conflict (same source) the file wins.

 */

#include <sys/inotify.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <cctype>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

using namespace std;
namespace fs = std::filesystem;

extern char **environ;

static const char *TEMPLATE_DIR = "/etc/nginx.template";
static const char *TARGET_DIR = "/etc/nginx";
static const char *SERVER_DIR = "/etc/nginx/server.d";
static const char *BASIC_AUTH_DIR = "/etc/nginx/basic-auth";
static const char *BASIC_AUTH_ENV_DIR = "/etc/nginx/basic-auth-env";
static const char *CONFIG_FILE = "/config/reverse-proxy.conf";
static const char *WATCH_CERTS = "/etc/letsencrypt/live";
static const char *WATCH_CONFIG = "/config";

static pid_t nginxPid = 0;

// --------------------------------------------------------------- helpers ---

static string env(const string &key, const string &def = "") {
  const char *v = getenv(key.c_str());
  return v ? string(v) : def;
}

// Split on any whitespace, dropping empty tokens.
static vector<string> tokens(const string &s) {
  vector<string> out;
  istringstream in(s);
  string t;
  while (in >> t)
    out.push_back(t);
  return out;
}

// ------------------------------------------------------------- settings ---
// Values rendered into the template as ${NAME}. The first three belong to the
// template of mwaeckerlin/nginx, whose environment the final stage does not
// inherit. An invalid value is replaced by the default with a warning, so it can
// neither break the configuration nor inject a directive.

enum class Kind { Number, Size, Time, Buffers };

struct Setting {
  const char *name;
  const char *def;
  Kind kind;
};

static const Setting SETTINGS[] = {
    {"WORKER_CONNECTIONS", "1024", Kind::Number},
    {"KEEPALIVE_TIMEOUT", "65", Kind::Time},
    {"CLIENT_MAX_BODY_SIZE", "0", Kind::Size},
    {"CLIENT_BODY_BUFFER_SIZE", "128k", Kind::Size},
    {"PROXY_BUFFERS", "32 4k", Kind::Buffers},
    {"PROXY_CONNECT_TIMEOUT", "1200", Kind::Time},
    {"PROXY_READ_TIMEOUT", "86400", Kind::Time},
    {"PROXY_SEND_TIMEOUT", "1200", Kind::Time},
    {"SEND_TIMEOUT", "1200", Kind::Time},
    {"HSTS_MAX_AGE", "31536000", Kind::Number},
};

// Length of the leading run of digits.
static size_t digits(const string &s, size_t from = 0) {
  size_t i = from;
  while (i < s.size() && isdigit(static_cast<unsigned char>(s[i])))
    ++i;
  return i - from;
}

static bool validSize(const string &s) {
  size_t n = digits(s);
  if (n == 0)
    return false;
  return n == s.size() || (n + 1 == s.size() && string("kKmMgG").find(s[n]) != string::npos);
}

static bool validValue(const string &s, Kind kind) {
  size_t n = digits(s);
  switch (kind) {
  case Kind::Number:
    return n > 0 && n == s.size();
  case Kind::Size:
    return validSize(s);
  case Kind::Time: {
    if (n == 0)
      return false;
    const string unit = s.substr(n);
    for (const char *u : {"", "ms", "s", "m", "h", "d", "w", "M", "y"})
      if (unit == u)
        return true;
    return false;
  }
  case Kind::Buffers:
    return n > 0 && n + 1 < s.size() && s[n] == ' ' && validSize(s.substr(n + 1));
  }
  return false;
}

static void applySettings() {
  for (const auto &setting : SETTINGS) {
    const char *value = getenv(setting.name);
    if (value && *value && validValue(value, setting.kind))
      continue;
    if (value && *value)
      cerr << "**** WARNING: ignoring invalid " << setting.name << "=" << value
           << ", using " << setting.def << endl;
    setenv(setting.name, setting.def, 1);
  }
}

// ------------------------------------------------ template substitution ---
// Same behaviour as envwrap: substitute ${VAR} from the environment in every
// file below the template and write the result into the target, replacing the
// target's previous content. Runs shell-free so it works in the scratch image.

static string substitute(const string &input) {
  string out = input;
  for (char **p = environ; *p; ++p) {
    string line(*p);
    auto eq = line.find('=');
    if (eq == string::npos)
      continue;
    const string needle = "${" + line.substr(0, eq) + "}";
    const string value = line.substr(eq + 1);
    size_t pos = 0;
    while ((pos = out.find(needle, pos)) != string::npos) {
      out.replace(pos, needle.size(), value);
      pos += value.size();
    }
  }
  return out;
}

static void renderTemplate() {
  if (!fs::exists(TEMPLATE_DIR))
    throw runtime_error(string("template not found: ") + TEMPLATE_DIR);
  // Overwrite in place rather than wiping the target: mounted data such as
  // /etc/nginx/basic-auth lives under the target and must not be removed. Stale
  // generated server blocks are cleared in generateServers().
  fs::create_directories(TARGET_DIR);

  for (const auto &entry : fs::recursive_directory_iterator(TEMPLATE_DIR)) {
    const auto rel = fs::relative(entry.path(), TEMPLATE_DIR);
    const fs::path dst = fs::path(TARGET_DIR) / rel;
    if (entry.is_directory()) {
      fs::create_directories(dst);
      continue;
    }
    fs::create_directories(dst.parent_path());
    ifstream in(entry.path(), ios::binary);
    string content((istreambuf_iterator<char>(in)),
                   istreambuf_iterator<char>());
    ofstream out(dst, ios::binary);
    out << substitute(content);
  }
}

// ------------------------------------------------------ configuration ------

struct Rule {
  bool forward; // true = forward, false = redirect
  string source;
  string target;
};

// Rule tokens are rendered verbatim into the generated nginx configuration:
// restrict them to a safe character set so a malformed or hostile token can
// neither break the configuration nor inject directives — one bad rule must
// never take all virtual hosts down.
static bool safeToken(const string &s) {
  if (s.empty() || s.front() == '/')
    return false;
  for (unsigned char c : s)
    if (!isalnum(c) && c != '.' && c != '_' && c != ':' && c != '/' && c != '-')
      return false;
  return true;
}

// Append a rule after validation; invalid rules are skipped with a warning.
static void addRule(bool forward, const string &source, const string &target,
                    vector<Rule> &out) {
  if (!safeToken(source) || !safeToken(target)) {
    cerr << "**** WARNING: ignoring invalid rule: " << source << ' ' << target
         << endl;
    return;
  }
  out.push_back({forward, source, target});
}

// Parse "<source> <target>" from a single line; ignores blank / comment lines.
static bool parsePair(const string &line, string &source, string &target) {
  string trimmed = line;
  auto hash = trimmed.find('#');
  if (hash != string::npos)
    trimmed = trimmed.substr(0, hash);
  auto t = tokens(trimmed);
  if (t.size() < 2)
    return false;
  source = t[0];
  target = t[1];
  return true;
}

static void appendRules(const string &block, bool forward, vector<Rule> &out) {
  istringstream in(block);
  string line;
  while (getline(in, line)) {
    string source, target;
    if (parsePair(line, source, target))
      addRule(forward, source, target, out);
  }
}

// Environment FORWARD / REDIRECT plus the file, merged. File wins on conflict
// (same source), so the file's rules replace any environment rule sharing the
// source. Environment rules are read first, then filtered, then the file rules
// are appended.
static vector<Rule> collectRules() {
  vector<Rule> envRules;
  appendRules(env("FORWARD"), true, envRules);
  appendRules(env("REDIRECT"), false, envRules);

  vector<Rule> fileRules;
  if (fs::exists(CONFIG_FILE)) {
    ifstream in(CONFIG_FILE);
    string line;
    while (getline(in, line)) {
      auto t = tokens(line.substr(0, line.find('#')));
      if (t.size() < 3)
        continue;
      if (t[0] == "forward")
        addRule(true, t[1], t[2], fileRules);
      else if (t[0] == "redirect")
        addRule(false, t[1], t[2], fileRules);
    }
  }

  vector<Rule> rules;
  for (const auto &e : envRules) {
    bool overridden = false;
    for (const auto &f : fileRules)
      if (f.source == e.source) {
        overridden = true;
        break;
      }
    if (!overridden)
      rules.push_back(e);
  }
  for (const auto &f : fileRules)
    rules.push_back(f);
  return rules;
}

// -------------------------------------------------- server generation ------

// The realm is rendered between quotes into auth_basic: a quote, backslash,
// semicolon or line break would end the directive and could switch the
// protection off, so such a realm is ignored with a warning and the host
// name serves as realm instead.
static string realmFromEnvironment() {
  static const string realm = [] {
    string value = env("BASIC_AUTH_REALM");
    for (unsigned char c : value)
      if (!isalnum(c) && c != ' ' && c != '.' && c != '_' && c != ':' && c != '/' &&
          c != '-' && c != '@' && c != '(' && c != ')' && c != ',') {
        cerr << "**** WARNING: ignoring invalid BASIC_AUTH_REALM, using the host name"
             << endl;
        return string();
      }
    return value;
  }();
  return realm;
}

// The more specific base path wins; at the same level a mounted file wins over
// an entry of BASIC_AUTH.
static string basicAuth(const string &fromurl, const string &frombase) {
  const string realm = realmFromEnvironment();
  const pair<string, string> levels[] = {
      {"/" + fromurl + "/" + frombase + ".htpasswd", fromurl + "/" + frombase},
      {"/" + fromurl + ".htpasswd", fromurl}};
  for (const auto &[file, name] : levels)
    for (const string dir : {BASIC_AUTH_DIR, BASIC_AUTH_ENV_DIR})
      if (fs::exists(dir + file))
        return "    auth_basic \"" + (realm.empty() ? name : realm) + "\";\n"
               "    auth_basic_user_file " + dir + file + ";\n";
  return "";
}

// True if PROXY_REDIRECT_OFF (whitespace separated list) contains this host+base.
static bool redirectOff(const string &key) {
  for (const auto &t : tokens(env("PROXY_REDIRECT_OFF")))
    if (t == key)
      return true;
  return false;
}

// Port of nginx-configure.sh forward(): proxy <source> to <target>.
static string forwardLocation(const string &fromurl, const string &frombase,
                              const string &source, const string &target) {
  string toscheme = "http://";
  string tgt = target;
  if (tgt.rfind("http://", 0) == 0 || tgt.rfind("https://", 0) == 0) {
    toscheme = tgt.substr(0, tgt.find("://")) + "://";
    tgt = tgt.substr(tgt.find("://") + 3);
  }
  string tobase, toport, tourl = tgt;
  if (auto s = tgt.find('/'); s != string::npos) {
    tobase = tgt.substr(s);
    if (!tobase.empty() && tobase.back() == '/')
      tobase.pop_back();
    tourl = tgt.substr(0, s);
  }
  if (auto c = tourl.find(':'); c != string::npos) {
    toport = ":" + tourl.substr(c + 1);
    tourl = tourl.substr(0, c);
  }
  string fromport = ":$port"; // source port defaults to the listen port

  ostringstream o;
  o << "  location " << frombase << "/ {\n";
  o << basicAuth(fromurl, frombase);
  o << "    include proxy.conf;\n";
  o << "    resolver 127.0.0.11:53 valid=30s;\n";
  o << "    set $tourl " << tourl << ";\n";
  o << "    if ($request_method ~ ^COPY$) {\n";
  o << "      rewrite " << tobase << "/(.*) " << frombase << "/$1 break;\n";
  o << "    }\n";
  o << "    proxy_cookie_domain " << tourl << " " << fromurl << ";\n";
  if (tobase + "/" != frombase + "/")
    o << "    proxy_cookie_path " << tobase << "/ " << frombase << "/;\n";
  o << "    proxy_pass " << toscheme << "$tourl" << toport << tobase << ";\n";
  if (redirectOff(fromurl + frombase))
    o << "    proxy_redirect off;\n";
  else
    o << "    proxy_redirect " << toscheme << "$tourl" << toport << tobase
      << "/ $scheme://" << fromurl << fromport << frombase << "/;\n";
  o << "  }\n";
  return o.str();
}

// Port of nginx-configure.sh redirect(): permanently redirect <source> to <target>.
static string redirectRewrite(const string &source, const string &target) {
  string tgt = target;
  if (!tgt.empty() && tgt.back() == '/')
    tgt.pop_back();
  auto slash = source.find('/');
  if (slash != string::npos) {
    string path = source.substr(slash + 1);
    return "  rewrite ^/" + path + "(/.*)?$ $scheme://" + tgt + "$1 permanent;\n";
  }
  return "  rewrite ^/$ $scheme://" + tgt + "/ permanent;\n";
}

// Split a source into virtual host (fromurl) and optional base path (frombase,
// leading slash, no trailing slash). Also strips an optional source port.
static void splitSource(const string &source, string &fromurl, string &frombase) {
  frombase.clear();
  fromurl = source;
  if (auto s = source.find('/'); s != string::npos) {
    frombase = source.substr(s);
    if (!frombase.empty() && frombase.back() == '/')
      frombase.pop_back();
    fromurl = source.substr(0, s);
  }
  if (auto c = fromurl.find(':'); c != string::npos)
    fromurl = fromurl.substr(0, c);
}

static string writeHTTP(const string &server, const string &content) {
  ostringstream o;
  o << "server { # redirect www to non-www\n"
       "  listen 8080;\n"
       "  server_name www." << server << ";\n"
       "  location /.well-known {\n"
       "      alias /acme/.well-known;\n"
       "  }\n"
       "  location / {\n"
       "    resolver 127.0.0.11:53 valid=30s;\n"
       "    return 302 http://" << server << "$request_uri;\n"
       "  }\n"
       "}\n"
       "server {\n"
       "  listen 8080;\n"
       "  server_name " << server << ";\n"
       "  set $port 8080;\n"
       "  error_page 502 /502.html;\n"
       "  error_page 504 /504.html;\n"
       "  error_page 404 /404.html;\n"
       "  location ~ ^/(502|504|404)\\.html$ {\n"
       "    root /etc/nginx/error/$lang;\n"
       "  }\n"
       "  location ~ ^/(502|504|404)\\.jpg$ {\n"
       "    root /etc/nginx/error;\n"
       "  }\n"
    << content
    << "  location /.well-known {\n"
       "      alias /acme/.well-known;\n"
       "  }\n"
       "}\n";
  return o.str();
}

static vector<string> g_generated; // server.d files written by the previous run

// HTTPS variant: served when a certificate for the domain exists and SSL is not
// disabled. http (and www) is redirected to https. Falls back to writeHTTP until
// the certificate appears, so a domain works before Let's Encrypt has issued it.
static string writeHTTPS(const string &server, const string &content) {
  const string live = "/etc/letsencrypt/live/" + server;
  ostringstream o;
  o << "server { # redirect http to https\n"
       "  listen 8080;\n"
       "  server_name " << server << " www." << server << ";\n"
       "  location /.well-known {\n"
       "      alias /acme/.well-known;\n"
       "  }\n"
       "  location / {\n"
       "    resolver 127.0.0.11:53 valid=30s;\n"
       "    return 302 https://" << server << "$request_uri;\n"
       "  }\n"
       "}\n"
       "server {\n"
       "  listen 8443 ssl;\n"
       "  http2 on;\n"
       "  server_name " << server << ";\n"
       "  set $port 8443;\n"
       "  add_header Strict-Transport-Security max-age=" << env("HSTS_MAX_AGE") << " always;\n"
       "  ssl_certificate " << live << "/fullchain.pem;\n"
       "  ssl_certificate_key " << live << "/privkey.pem;\n"
       "  error_page 502 /502.html;\n"
       "  error_page 504 /504.html;\n"
       "  error_page 404 /404.html;\n"
       "  location ~ ^/(502|504|404)\\.html$ {\n"
       "    root /etc/nginx/error/$lang;\n"
       "  }\n"
       "  location ~ ^/(502|504|404)\\.jpg$ {\n"
       "    root /etc/nginx/error;\n"
       "  }\n"
    << content
    << "  location /.well-known {\n"
       "      alias /acme/.well-known;\n"
       "  }\n"
       "}\n";
  return o.str();
}

static bool sslEnabled() { return env("SSL") != "off"; }

static bool hasCertificate(const string &server) {
  return fs::exists("/etc/letsencrypt/live/" + server + "/fullchain.pem") &&
         fs::exists("/etc/letsencrypt/live/" + server + "/privkey.pem");
}

// BASIC_AUTH and the file named by BASIC_AUTH_FILE (a docker secret) hold one
// entry per line, `<host>[/<base>] <user>:<password hash>`; the entries of one
// host and base become one htpasswd file below BASIC_AUTH_ENV_DIR.
static void writeBasicAuthFromEnvironment() {
  error_code ec;
  fs::remove_all(BASIC_AUTH_ENV_DIR, ec);
  string entries = env("BASIC_AUTH");
  const string file = env("BASIC_AUTH_FILE");
  if (!file.empty()) {
    ifstream in(file);
    if (in)
      entries += "\n" + string((istreambuf_iterator<char>(in)), istreambuf_iterator<char>());
    else
      cerr << "**** WARNING: cannot read BASIC_AUTH_FILE " << file << endl;
  }
  istringstream lines(entries);
  string line;
  while (getline(lines, line)) {
    auto t = tokens(line.substr(0, line.find('#')));
    if (t.empty())
      continue;
    const auto colon = t.size() == 2 ? t[1].find(':') : string::npos;
    if (t.size() != 2 || !safeToken(t[0]) || t[0].find("..") != string::npos ||
        colon == 0 || colon == string::npos || colon + 1 == t[1].size()) {
      // the line may carry a password hash, so only the host is named
      cerr << "**** WARNING: ignoring invalid BASIC_AUTH entry for " << t[0] << endl;
      continue;
    }
    string fromurl, frombase;
    splitSource(t[0], fromurl, frombase);
    const fs::path path = fs::path(BASIC_AUTH_ENV_DIR + ("/" + fromurl) +
                                   (frombase.empty() ? "" : "/" + frombase) + ".htpasswd");
    fs::create_directories(path.parent_path());
    ofstream(path, ios::app) << t[1] << "\n";
  }
}

static void generateServers() {
  fs::create_directories(SERVER_DIR);
  // Remove the server blocks generated last time (e.g. for a domain that has
  // since been removed from the configuration); template files are left alone.
  for (const auto &name : g_generated)
    fs::remove(fs::path(SERVER_DIR) / name);
  g_generated.clear();

  vector<string> order;                    // server names in first-seen order
  unordered_map<string, string> content;   // server name -> accumulated content

  for (const auto &rule : collectRules()) {
    string fromurl, frombase;
    splitSource(rule.source, fromurl, frombase);
    if (content.find(fromurl) == content.end())
      order.push_back(fromurl);
    if (rule.forward)
      content[fromurl] += forwardLocation(fromurl, frombase, rule.source, rule.target);
    else
      content[fromurl] += redirectRewrite(rule.source, rule.target);
  }

  for (const auto &server : order) {
    const string name = server + ".conf";
    ofstream out(fs::path(SERVER_DIR) / name, ios::binary);
    if (sslEnabled() && hasCertificate(server))
      out << writeHTTPS(server, content[server]);
    else
      out << writeHTTP(server, content[server]);
    g_generated.push_back(name);
  }
}

// ---------------------------------------------------------- lifecycle ------

static void runOpenssl(const string &out, const string &bits) {
  pid_t p = fork();
  if (p == -1)
    return;
  if (p == 0) {
    execl("/usr/bin/openssl", "openssl", "dhparam", "-out", out.c_str(),
          bits.c_str(), nullptr);
    _exit(1);
  }
  int status = 0;
  waitpid(p, &status, 0);
}

// Ensure /etc/nginx/dhparam.pem exists -- the base ssl.conf requires it. The DH
// parameters are generated at start (not baked into the image) with DHPARAM bits
// (default 4096) and kept on the persistent DHPARAM_FILE, so they are generated
// only once. A pre-generated file (e.g. mounted) is used as-is.
static void ensureDhparam() {
  const string persistent = env("DHPARAM_FILE", "/etc/letsencrypt/dhparam.pem");
  const string target = string(TARGET_DIR) + "/dhparam.pem";
  const string bits = env("DHPARAM", "4096");
  if (!fs::exists(persistent))
    runOpenssl(persistent, bits); // no-op if the path is not writable
  error_code ec;
  if (fs::exists(persistent))
    fs::copy_file(persistent, target, fs::copy_options::overwrite_existing, ec);
  else if (!fs::exists(target))
    runOpenssl(target, bits);
}

static void rebuild() {
  applySettings();
  renderTemplate();
  writeBasicAuthFromEnvironment();
  ensureDhparam();
  generateServers();
}

static void startNginx() {
  nginxPid = fork();
  if (nginxPid == -1)
    exit(EXIT_FAILURE);
  if (nginxPid != 0)
    return;
  cout << "---- STARTING PROCESS NGINX, PID=" << getpid() << endl;
  execl("/usr/sbin/nginx", "/usr/sbin/nginx", nullptr);
  perror("execl nginx");
  exit(EXIT_FAILURE);
}

// Forward termination to nginx for a graceful shutdown, then leave. As PID 1 the
// kernel applies no default action, so without this handler `docker stop` would
// be ignored until SIGKILL and nginx would die abruptly.
static void onTerminate(int) {
  if (nginxPid > 0)
    kill(nginxPid, SIGQUIT); // graceful stop
  int status = 0;
  if (nginxPid > 0)
    waitpid(nginxPid, &status, 0);
  _exit(0);
}

int main() try {
  signal(SIGTERM, onTerminate);
  signal(SIGINT, onTerminate);

  rebuild();
  startNginx();

  while (true) {
    pid_t watcher = fork();
    if (watcher == -1)
      exit(EXIT_FAILURE);
    if (watcher == 0) {
      cout << "---- WATCHING CERTIFICATES AND CONFIGURATION, PID=" << getpid()
           << endl;
      execl("/usr/bin/inotifywait", "/usr/bin/inotifywait", "-q", "-r", "-e",
            "close_write", "-e", "create", "-e", "moved_to", "-e", "delete",
            WATCH_CERTS, WATCH_CONFIG, nullptr);
      perror("execl inotifywait");
      exit(EXIT_FAILURE);
    }

    int status = 0;
    pid_t done = wait(&status);
    if (done == nginxPid) {
      cerr << "**** ERROR: NGINX TERMINATED, STATUS=" << WEXITSTATUS(status)
           << endl;
      exit(EXIT_FAILURE);
    }
    if (done == watcher) {
      if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
        cerr << "**** ERROR: WATCHING FAILED, STATUS=" << WEXITSTATUS(status)
             << endl;
        exit(EXIT_FAILURE);
      }
      cout << "**** configuration or certificate changed, reloading" << endl;
      rebuild();
      if (nginxPid > 0)
        kill(nginxPid, SIGHUP); // graceful reload
    }
  }
  return 0;
} catch (const exception &e) {
  cerr << "EXCEPTION: " << e.what() << endl;
  return 1;
}

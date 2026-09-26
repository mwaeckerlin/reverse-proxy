# Tests

Register of all tests, sorted by the [FEATURES.md](FEATURES.md) number each test covers. `npm test` runs everything; the guard `tests/docs-contract.sh` fails when a feature has no test entry here or a test carries a skip marker.

## End-to-end HTTP

pytest runs against the real compose stack of `tests/e2e/`.

- **F1** `test_forward.py` › test_localhost_forwarded_to_localserver, test_demo_forwarded_to_demo_backend, test_test_forwarded_to_test_backend — each host reaches its backend.
- **F1** `test_forward.py` › test_forward_isolates_backends — a host never reaches another host's backend.
- **F1** `test_forward.py` › test_path_based_forward, test_path_forward_leaves_root_unconfigured — a forward with a base path, and the root of that host stays unconfigured.
- **F2** `test_redirect.py` › test_extern_redirects_permanently, test_redirect_with_base_path, test_redirect_base_leaves_other_paths — permanent redirects, with and without base path.
- **F2** `test_file_config.py` › test_file_redirect_is_permanent — a redirect from the file.
- **F3** `test_redirect.py` › test_www_prefix_redirects_to_bare_host — `www.` goes to the bare host.
- **F4** `test_mixed_config.py` › test_env_only_rule_applies — a rule from the environment.
- **F5** `test_file_config.py` › test_file_forward_is_served, test_file_unknown_host_not_forwarded — a forward from the file, nothing else is forwarded.
- **F6** `test_mixed_config.py` › test_file_only_rule_applies, test_file_wins_on_conflict — both sources, the file wins.
- **F7** `test_reload.py` › test_config_file_change_reloads_route — writing the file reloads the route.
- **F7** `tests/e2e-https/test_https.py` › test_https_serves_backend_after_certificate_issued — the certificate that appears is served without a restart.
- **F8** `test_invalid_config.py` › test_valid_rule_after_invalid_is_served, test_invalid_forward_creates_no_route, test_other_hosts_unaffected_by_invalid_rules — invalid rules are dropped, the rest works.
- **F9** `test_maintenance.py` › test_unreachable_backend_returns_maintenance_502, test_unknown_host_is_not_forwarded — maintenance and not found pages.
- **F10** `test_basic_auth.py` › test_no_credentials_is_unauthorized, test_wrong_credentials_is_unauthorized, test_correct_credentials_pass_through — the protection works.
- **F10** `test_basic_auth.py` › test_default_realm_is_the_host, test_realm_from_environment — the realm is the host, or `BASIC_AUTH_REALM`.
- **F10** `test_basic_auth.py` › test_hostile_realm_keeps_the_protection — a realm that closes the quote is ignored and the host stays protected (regression: `x"; auth_basic off; #` switched the protection off).
- **F11** `test_proxy_redirect.py` › test_backend_redirect_is_rewritten_to_the_public_host, test_proxy_redirect_off_passes_the_backend_address — rewriting and `PROXY_REDIRECT_OFF`.
- **F12** `test_headers.py` › test_headers_added_for_headerless_backend, test_headers_not_duplicated_for_backend_with_own_headers — the headers, exactly once.
- **F12** `tests/e2e-https/test_https.py` › test_https_sets_hsts_header — HSTS on HTTPS.
- **F14** `test_startup.py` › test_proxy_boots_via_default_command — every proxy of the stack generates its DH parameters (`DHPARAM=512`, no file) and boots.
- **F15** `test_startup.py` › test_proxy_boots_via_default_command — the container boots without a command override.

## End-to-end HTTPS

pytest runs against the stack of `tests/e2e-https/`, which brings its own ACME server.

- **F13** `test_https.py` › test_https_serves_backend_after_certificate_issued, test_https_presents_the_issued_certificate, test_http_redirects_to_https_once_secured, test_www_over_http_redirects_to_https — the issued certificate is served, HTTP goes to HTTPS.
- **F14** `test_https.py` › test_https_serves_backend_after_certificate_issued — a ready-made `dhparam.pem` on `DHPARAM_FILE` is used as it is.

## Image contract

- **F16** `tests/image-contract.sh` › no sh, no bash, no busybox, no perl — the image is headless.

## Workflow contract

- **F17** `tests/workflow-contract.sh` of `mwaeckerlin/scratch` — the reusable workflow selects exactly the images a repository publishes; this repository calls it from `.github/workflows/docker.yml`.

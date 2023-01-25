#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdlib.h>
#include <signal.h>
#include <iostream>
using namespace std;

pid_t pid(0);
pid_t pidl(0);

void startNginx()
{
    pid = fork();
    if (pid == -1)
        exit(EXIT_FAILURE);
    if (pid != 0)
        return;
    cout << "---- STARTING PROCESS NGINX, PID=" << getpid() << endl;
    execl("/usr/sbin/nginx", "/usr/sbin/nginx", nullptr);
    exit(EXIT_FAILURE); // shouldn't get here
}

void loop()
{
    pidl = fork();
    if (pidl == -1)
        exit(EXIT_FAILURE);
    if (pidl == 0)
    {
        cout << "---- CHECKING FOR NEW CERTIFICATES, PID=" << getpid() << endl;
        execl("/usr/bin/inotifywait", "/usr/bin/inotifywait", "-q", "-e", "close_write", "/etc/letsencrypt/live", nullptr);
        exit(EXIT_FAILURE); // shouldn't get here
    }
    else
    {
        int stat = 0;
        pid_t p = wait(&stat);
        if (p == pid)
        {
            cerr << "**** ERROR: NGINX TERMINATED, STATUS=" << WEXITSTATUS(stat) << endl;
            exit(EXIT_FAILURE);
        }
        if (p == pidl)
            if (WEXITSTATUS(stat) != 0)
            {
                cerr << "**** ERROR: WATCHING CERTIFICATES FAILED, STATUS=" << WEXITSTATUS(stat) << endl;
                exit(EXIT_FAILURE);
            }
            else
            {
                kill(pid, SIGHUP);
            }
        else
        {
            cerr << "**** ERROR: UNKNOWN CHILD, PID=" << p << ", STATUS" << WEXITSTATUS(stat) << endl;
            exit(EXIT_FAILURE);
        }
    }
}

int main()
{
    startNginx();
    while (true)
        loop();
    return 0;
}
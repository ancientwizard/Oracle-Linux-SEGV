
all: db-thread thr-id

run: db-thread
	./db-handle-size
#	./db-thread -t 8

clean:
	rm -f db-thread thr-id db-handle-size

db-thread: Makefile clean db-thread.c db-handle-size.c
#	Centos/RHEL - based on RPM install
#	gcc -o db-thread db-thread.c -I/usr/include/oracle/23/client64 -L${ORACLE_HOME}/lib -lclntsh -lpthread -O0 -g
#	Ubuntu - based on Oracle TARBALL of SDK
	gcc -o db-thread db-thread.c -I/usr/lib/oracle/23/client64/sdk/include -L${ORACLE_HOME}/lib -lclntsh -lpthread -O2
#	gcc -o db-thread db-thread.c -I/usr/lib/oracle/23/client64/sdk/include -L${ORACLE_HOME}/lib -lclntsh -lpthread -O0 -g
	gcc -o db-handle-size db-handle-size.c -I/usr/lib/oracle/23/client64/sdk/include -L${ORACLE_HOME}/lib -lclntsh -lpthread -O2


thr-id: Makefile thr-id.c
	gcc -o thr-id thr-id.c -lpthread


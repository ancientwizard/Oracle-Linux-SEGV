
all: db-thread thr-id

run: db-thread
	./db-thread -t 8

clean:
	rm -f db-thread thr-id

db-thread: db-thread.c Makefile
#	Ubuntu - based on Oracle TARBALL of SDK
	gcc -o db-thread db-thread.c -I/usr/lib/oracle/23/client64/sdk/include -L${ORACLE_HOME}/lib -lclntsh -lpthread -O0 -g

thr-id: thr-id.c Makefile
	gcc -o thr-id thr-id.c -lpthread


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <oci.h>
#include <unistd.h> // For getopt

// Structure to hold thread status
typedef struct {
    int connection_status;
    int ping_status;
    char error_message[512];
} ThreadStatus;

// Thread function
void* db_thread_function(void* arg) {
    ThreadStatus* status = (ThreadStatus*)arg;
    OCIEnv* env = NULL;
    OCIError* err = NULL;
    OCISvcCtx* svc = NULL;
    int retval;

    // Get credentials from environment variables
    const char* schema = getenv("ORA_SCHEMA");
    const char* passwd = getenv("ORA_PASSWD");
    const char* dbname = getenv("ORA_DBNAME");

    // Initialize OCI environment
    if (OCIEnvCreate(&env, OCI_THREADED, NULL, NULL, NULL, NULL, 0, NULL) != OCI_SUCCESS) {
        snprintf(status->error_message, sizeof(status->error_message), "Failed to initialize OCI environment");
        status->connection_status = -1;
        pthread_exit(NULL);
    }

    // Allocate error handle
    OCIHandleAlloc(env, (void**)&err, OCI_HTYPE_ERROR, 0, NULL);

    // Connect to the database
    retval = OCILogon(env, err, &svc, (OraText*)schema, strlen(schema),
                      (OraText*)passwd, strlen(passwd),
                      (OraText*)dbname, strlen(dbname));
    if (retval != OCI_SUCCESS) {
        OCIErrorGet(err, 1, NULL, &retval, (OraText*)status->error_message, sizeof(status->error_message), OCI_HTYPE_ERROR);
        status->connection_status = -1;
        goto cleanup;
    }
    status->connection_status = 0;

    // Perform ping
    retval = OCIPing(svc, err, OCI_DEFAULT);
    if (retval != OCI_SUCCESS) {
        OCIErrorGet(err, 1, NULL, &retval, (OraText*)status->error_message, sizeof(status->error_message), OCI_HTYPE_ERROR);
        status->ping_status = -1;
        goto cleanup;
    }
    status->ping_status = 0;

cleanup:
    // Disconnect and clean up
    if (svc) OCILogoff(svc, err);
    if (err) OCIHandleFree(err, OCI_HTYPE_ERROR);
    if (env) OCIHandleFree(env, OCI_HTYPE_ENV);

    pthread_exit(NULL);
}

int main(int argc, char* argv[]) {
    int num_threads = 1; // Default number of threads
    int opt;

    // Parse command-line arguments
    while ((opt = getopt(argc, argv, "t:")) != -1) {
        switch (opt) {
            case 't':
                num_threads = atoi(optarg);
                if (num_threads <= 0) {
                    fprintf(stderr, "Invalid number of threads: %s\n", optarg);
                    return EXIT_FAILURE;
                }
                break;
            default:
                fprintf(stderr, "Usage: %s [-t threads]\n", argv[0]);
                return EXIT_FAILURE;
        }
    }

    // Validate environment variables
    const char* schema = getenv("ORA_SCHEMA");
    const char* passwd = getenv("ORA_PASSWD");
    const char* dbname = getenv("ORA_DBNAME");

    if (!schema || !passwd || !dbname) {
        fprintf(stderr, "Error: ORA_SCHEMA, ORA_PASSWD, and ORA_DBNAME environment variables must be defined.\n");
        return EXIT_FAILURE;
    }

    pthread_t* threads = malloc(num_threads * sizeof(pthread_t));
    ThreadStatus* statuses = malloc(num_threads * sizeof(ThreadStatus));

    if (!threads || !statuses) {
        perror("Failed to allocate memory");
        free(threads);
        free(statuses);
        return EXIT_FAILURE;
    }

    for ( int l = 1 ; l < 33 ; l ++ )
    {

        // Create threads
        for (int i = 0; i < num_threads; i++) {
            memset(&statuses[i], 0, sizeof(ThreadStatus));
            if (pthread_create(&threads[i], NULL, db_thread_function, &statuses[i]) != 0) {
                perror("Failed to create thread");
                num_threads = i; // Adjust the number of threads to join
                break;
            }
        }

        // Wait for threads to complete
        for (int i = 0; i < num_threads; i++) {
            pthread_join(threads[i], NULL);
            printf(" INFO: LOOP %d Thread %d", l, i + 1);
            if (statuses[i].connection_status == 0 && statuses[i].ping_status == 0) {
                printf(" Database connection and ping successful.\n");
            } else {
                printf(" Error: %s\n", statuses[i].error_message);
            }
        }
    }

    free(threads);
    free(statuses);

    printf("\n EXIT SUCCESS\n\n");

    return EXIT_SUCCESS;
}

// END

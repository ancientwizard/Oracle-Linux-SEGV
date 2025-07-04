#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <pthread.h>
#include <oci.h>
#include <unistd.h> // For getopt

#define HANDLE_SAMPLE_SIZE 10

typedef struct hi_t HandleInspect;

typedef union {
    HandleInspect * handle;
    uint8_t         address[8];
} peek_t;

struct hi_t {
    uint8_t     leader[8];
    peek_t      a;
    peek_t      b;
    peek_t      c;
};

void dump_memory(void *ptr, size_t size) {
    unsigned char *data = (unsigned char*) ptr;
    for (size_t i = 0; i < size; i++) {
        printf(" 0x%02x", data[i]);
        if ((i + 1) % 8 == 0) printf("\n");
    }
    printf("\n");
}

// Detect ENV handle size (a guess)
void* db_eng_size()
{
    OCIEnv* envset[HANDLE_SAMPLE_SIZE]; // OCI environment handle (OCIEnvNlsCreate)
    sword   status  = OCI_SUCCESS;
    int     size    = 0;;
    OCIEnv* env     = NULL; // OCI environment handle (OCIEnvNlsCreate)

    for ( int i = 0 ; i < HANDLE_SAMPLE_SIZE ; i++ )
    {
    //  if (( status = OCIEnvNlsCreate(&envset[i], OCI_DEFAULT,  0, NULL, NULL, NULL, 0, NULL, 0, 0)) != OCI_SUCCESS)
        if (( status = OCIEnvNlsCreate(&envset[i], OCI_THREADED, 0, NULL, NULL, NULL, 0, NULL, 0, 0)) != OCI_SUCCESS)
            printf("Failed to initialize OCI (envset[%d]) environment", i);
    }

    for ( int i = 0 ; i < HANDLE_SAMPLE_SIZE ; i++ )
    {
        if ( i > 0 )
        {
        //  printf("OCIEnvNlsCreate(handle=%ld,...) %p %p\n", 0l, envset[i], envset[i-1] );
            printf("OCIEnvNlsCreate(handle=%ld,...) %p\n"
                ,(long)( ((char*)envset[i]) - (char*)(envset[i-1] ))
                , envset[i-1]);
        }
        dump_memory(envset[i],64); 
    }

    for ( int i = 0 ; i < HANDLE_SAMPLE_SIZE ; i++ )
    {
        env = envset[i];
        if (env && (status = OCIHandleFree(env, OCI_HTYPE_ENV)) != OCI_SUCCESS )
            fprintf(stderr, "OCIHandleFree(env, OCI_HTYPE_ENV) returned %d\n", status);
        envset[i] = NULL;
    }

    printf("SIZEOF: HandleInspect = %lu\n", sizeof(HandleInspect));
}

// Thread function
/*
void* db_thread_function(void* arg)
{
    ThreadStatus* t_status = (ThreadStatus*)arg;
    OCIEnv*     mng_env = NULL; // OCI environment handle (OCIEnvNlsCreate)
    OCIEnv*     envhp   = NULL; // OCI environment handle (OCIEnvNlsCreate)
    OCIError*   errhp   = NULL; // OCI error handle
    OCIServer*  srvhp   = NULL; // OCI server handle
    OCISvcCtx*  svchp   = NULL; // OCI service context handle
    OCISession* seshp   = NULL; // OCI session handle
    sword status;

    // Get credentials from environment variables
    const char* schema = getenv("ORA_SCHEMA");
    const char* passwd = getenv("ORA_PASSWD");
    const char* dbname = getenv("ORA_DBNAME");

//  if (OCIEnvCreate(&env, OCI_THREADED, NULL, NULL, NULL, NULL, 0, NULL) != OCI_SUCCESS) {

    // Initialize OCI environment - mimic what is seen in DBD::Oracle ->> OCI_DEFAULT
    if (( status = OCIEnvNlsCreate(&mng_env, OCI_DEFAULT, 0, NULL, NULL, NULL, 0, NULL, 0, 0)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to initialize OCI (mng_env) environment");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // DBD::Oracle uses this function. Works here OK ->> OCI_THREADED
    if (( status = OCIEnvNlsCreate(&envhp, OCI_THREADED, 0, NULL, NULL, NULL, 0, NULL, 0, 0)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to initialize OCI environment");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // Allocate error handle
    if (( status = OCIHandleAlloc(envhp, (void**)&errhp, OCI_HTYPE_ERROR, 0, NULL)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to allocate OCI error handle");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // Allocate server handle
    if (( status = OCIHandleAlloc(envhp, (void**)&srvhp, OCI_HTYPE_SERVER, 0, NULL)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to allocate OCI server handle");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // CTX: Allocate service context handle
    if (( status = OCIHandleAlloc(envhp, (void**)&svchp, OCI_HTYPE_SVCCTX, 0, NULL)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to allocate OCI service handle");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // Allocate session handle (dbdcnx.c, #339)
    if (( status = OCIHandleAlloc(envhp, (void**)&seshp, OCI_HTYPE_SESSION, 0, NULL)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to allocate OCI session handle");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // Attach to the server (dbdcnx.c, :#346)
    if (( status = OCIServerAttach(srvhp, errhp, (OraText*)dbname, strlen(dbname), OCI_DEFAULT)) != OCI_SUCCESS) {
        OCIErrorGet(errhp, 1, NULL, &status, (OraText*)t_status->error_message, sizeof(t_status->error_message), OCI_HTYPE_ERROR);
        t_status->connection_status = -1;
        goto cleanup;
    }

    // Set the server handle in the service context (dbdcnx.c, L#353)
    if (( status = OCIAttrSet(svchp, OCI_HTYPE_SVCCTX, srvhp, 0, OCI_ATTR_SERVER, errhp)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to set server handle in service context");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // SET USERNAME (dbdcnx.c, L#368)
    if (( status = OCIAttrSet(seshp, OCI_HTYPE_SESSION, (void*)schema, strlen(schema), OCI_ATTR_USERNAME, errhp)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to set username in session handle");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // SET PASSWORD (dbdcnx.c, L#379)
    if (( status = OCIAttrSet(seshp, OCI_HTYPE_SESSION, (void*)passwd, strlen(passwd), OCI_ATTR_PASSWORD, errhp)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to set password in session handle");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // Connect to the database using OCISessionBegin (dbdcnx.c, L#405)
    if (( status = OCISessionBegin(svchp, errhp, seshp, OCI_CRED_RDBMS, OCI_DEFAULT)) != OCI_SUCCESS) {
        OCIErrorGet(errhp, 1, NULL, &status, (OraText*)t_status->error_message, sizeof(t_status->error_message), OCI_HTYPE_ERROR);
        t_status->connection_status = status;
        goto cleanup;
    }

    // Set the session handle in the service context (dbdcnx.c, L#410)
    if (( status = OCIAttrSet(svchp, OCI_HTYPE_SVCCTX, seshp, 0, OCI_ATTR_SESSION, errhp)) != OCI_SUCCESS) {
        snprintf(t_status->error_message, sizeof(t_status->error_message), "Failed to set session handle in service context");
        t_status->connection_status = status;
        pthread_exit(NULL);
    }

    // status = OCILogon(envhp, errhp, &svchp, (OraText*)schema, strlen(schema),
    //                   (OraText*)passwd, strlen(passwd),
    //                   (OraText*)dbname, strlen(dbname));
    // if (status != OCI_SUCCESS) {
    //     OCIErrorGet(errhp, 1, NULL, &status, (OraText*)t_status->error_message, sizeof(t_status->error_message), OCI_HTYPE_ERROR);
    //     t_status->connection_status = status;
    //     goto cleanup;
    // }
    // t_status->connection_status = 0;

    // Perform ping
    status = OCIPing(svchp, errhp, OCI_DEFAULT);
    if (status != OCI_SUCCESS) {
        OCIErrorGet(errhp, 1, NULL, &status, (OraText*)t_status->error_message, sizeof(t_status->error_message), OCI_HTYPE_ERROR);
        t_status->ping_status = status;
        goto cleanup;
    }
    t_status->ping_status = 0;

cleanup:

    // Disconnect and clean up using OCISessionEnd && OCIServerDetach
    if (seshp && (status = OCISessionEnd(svchp, errhp, seshp, OCI_DEFAULT)) != OCI_SUCCESS) {
        OCIErrorGet(errhp, 1, NULL, &status, (OraText*)t_status->error_message, sizeof(t_status->error_message), OCI_HTYPE_ERROR);
        t_status->connection_status = status;
    }

    if (srvhp && (status = OCIServerDetach(srvhp, errhp, OCI_DEFAULT)) != OCI_SUCCESS) {
        OCIErrorGet(errhp, 1, NULL, &status, (OraText*)t_status->error_message, sizeof(t_status->error_message), OCI_HTYPE_ERROR);
        t_status->connection_status = status;
    }

    // This PAIRS with OCILogon
    // if (svchp && (status = OCILogoff(svchp, errhp)) != OCI_SUCCESS )
    //     fprintf(stderr, "OCILogOff(svc,errhp) returned %d\n", status);

    if (seshp && (status = OCIHandleFree(seshp, OCI_HTYPE_SESSION)) != OCI_SUCCESS )
        fprintf(stderr, "OCIHandleFree(seshp, OCI_HTYPE_SESSION) returned %d\n", status);
    if (errhp && (status = OCIHandleFree(errhp, OCI_HTYPE_ERROR)) != OCI_SUCCESS )
        fprintf(stderr, "OCIHandleFree(errhp, OCI_HTYPE_ERROR) returned %d\n", status);
    if (envhp && (status = OCIHandleFree(envhp, OCI_HTYPE_ENV)) != OCI_SUCCESS )
        fprintf(stderr, "OCIHandleFree(envhp, OCI_HTYPE_ENV) returned %d\n", status);
    if (mng_env && (status = OCIHandleFree(mng_env, OCI_HTYPE_ENV)) != OCI_SUCCESS )
        fprintf(stderr, "OCIHandleFree(mng_env, OCI_HTYPE_ENV) returned %d\n", status);

    pthread_exit(NULL);
}
*/

int main(int argc, char* argv[]) {
    int opt;

    // Parse command-line arguments
/*
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
*/

    // Validate environment variables
//  const char* schema = getenv("ORA_SCHEMA");
//  const char* passwd = getenv("ORA_PASSWD");
//  const char* dbname = getenv("ORA_DBNAME");

//  if (!schema || !passwd || !dbname) {
//      fprintf(stderr, "Error: ORA_SCHEMA, ORA_PASSWD, and ORA_DBNAME environment variables must be defined.\n");
//      return EXIT_FAILURE;
//  }

//  pthread_t* threads = malloc(num_threads * sizeof(pthread_t));
//  ThreadStatus* statuses = malloc(num_threads * sizeof(ThreadStatus));

//  if (!threads || !statuses) {
//      perror("Failed to allocate memory");
//      free(threads);
//      free(statuses);
//      return EXIT_FAILURE;
//  }

    db_eng_size();

    return EXIT_SUCCESS;
}

// vim: expandtab number tabstop=4 shiftwidth=4
// END

#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>

int main(int argc, const char *argv[]) {
    
    char *src_root = getenv("SRCROOT");
    char *project_name = getenv("PROJECT_NAME");
    char *script_name = getenv("SCRIPT_NAME");
    char *action = getenv("ACTION");
    
    if (src_root == NULL || project_name == NULL || script_name == NULL || action == NULL) {
        printf("Error: Missing variables.\n");
        return 1;
    }
    
    size_t command_size = strlen(src_root) + strlen("/") + strlen(script_name) + strlen(" ") + strlen(action) + strlen(" ") + strlen(project_name) + 1;
    char *cmd_run = calloc(command_size, sizeof(char));
    sprintf(cmd_run, "%s/%s %s %s", src_root, script_name, action, project_name);
    
    if (system(cmd_run) != 0) {
        printf("Error: Failed to run command.\n");
    }
    
    free(cmd_run);
    return 0;
    
}

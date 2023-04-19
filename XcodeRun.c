//
//  main.c
//  XcodeRun
//
//  Created by Damian Dudycz on 16/04/2023.
//

#include <stdio.h>
#include <stdlib.h>

int main(int argc, const char * argv[]) {
    char *filePath = __FILE__;
    printf("%s\n", filePath);
    system("cd /Users/damiandudycz/Documents/Embeded/HelloWorld; ./scripts/05-run.sh HelloWorld");
    return 0;
}

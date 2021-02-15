/*
 * MIT License
 *
 * Copyright (c) 2021 Hajime Nakagami<nakagami@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
*/
#include <stdio.h>
#define	SLONG long
#define SCHAR char

// curl -O https://raw.githubusercontent.com/FirebirdSQL/firebird/master/src/include/gen/msgs.h
// cc errmsgs.c
// ./a.out


#include "msgs.h"   

int main(int argc, char *argv[])
{
    int i;
    FILE *fp = fopen("../src/errmsgs.jl", "w");

    fprintf(fp, "\
#############################################################################\n\
# The contents of this file are subject to the Interbase Public\n\
# License Version 1.0 (the \"License\"); you may not use this file\n\
# except in compliance with the License. You may obtain a copy\n\
# of the License at http://www.Inprise.com/IPL.html\n\
#n\
# Software distributed under the License is distributed on an\n\
# \"AS IS\" basis, WITHOUT WARRANTY OF ANY KIND, either express\n\
# or implied. See the License for the specific language governing\n\
# rights and limitations under the License.\n\n");
    fprintf(fp, "# generated by ../misc/errmsgs.c\n\n");
    fprintf(fp, "function get_errmsgs()::Vector{UInt32, String}\n");
    fprintf(fp, "    Dict(\n");
    for (i = 0; messages[i].code_text; i++) {
        fprintf(fp, "        %ld => \"\"\"%s\\n\"\"\",\n", messages[i].code_number, messages[i].code_text);
    }
    fprintf(fp, "    )\n");
    fprintf(fp, "end");

    fclose(fp);
    return 0;
}
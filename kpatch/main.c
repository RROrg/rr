/*
 * Copyright (c) 2022 Fabio Belavenuto <belavenuto@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */
/**
 * Converted from php code by Fabio Belavenuto <belavenuto@gmail.com>
 * 
 * A quick tool for patching the boot_params check in the DSM kernel image
 * This lets you tinker with the initial ramdisk contents without disabling mount() features and modules loading
 *
 * The overall pattern we need to find is:
 *  - an CDECL function
 *  - does "LOCK OR [const-ptr],n" 4x
 *  - values of ORs are 1/2/4/8 respectively
 *  - [const-ptr] is always the same
 *
 * Added patch for CMOS_WRITE by Fabio Belavenuto
 * 
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <getopt.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdarg.h>
#include <gelf.h>

const int DIR_FWD = 1;
const int DIR_RWD = -1;

/* Variables */
int           fd, verbose = 1, read_only = 0;
Elf           *elfHandle;
GElf_Ehdr     elfExecHeader;
uint64_t      orPos[4], fileSize, rodataAddr, rodataOffs, initTextOffs;
unsigned char *fileData;

/*****************************************************************************/
void errorMsg(char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fprintf(stderr, "\n");
    exit(1);
}

/*****************************************************************************/
void errorNum() {
    char str[100] = {0};
    perror(str);
    exit(2);
}

/*****************************************************************************/
void elfErrno() {
   int err;

    if ((err = elf_errno()) != 0) {
        fprintf(stderr, "%s\n", elf_errmsg(err));
        exit(3);
    }
}

/*****************************************************************************/
//Finding a function boundary is non-trivial really as patters can vary, we can have multiple exit points, and in CISC
// there are many things which may match e.g. "PUSH EBP". Implementing even a rough disassembler is pointless.
//However, we can certainly cheat here as we know with CDECL a non-empty function will always contain one or more
// PUSH (0x41) R12-R15 (0x54-57) sequences. Then we can search like a 1K forward for these characteristic LOCK OR.
uint64_t findPUSH_R12_R15_SEQ(uint64_t start) {
    uint64_t i;

    for (i = start; i < fileSize; i++) {
        if (fileData[i] == 0x41 && (fileData[i+1] >= 0x54 && fileData[i+1] <= 0x57)) {
            return i;
        }
    }
    return -1;
}

/*****************************************************************************/
//[0xF0, 0x80, null, null, null, null, null, 0xXX],
uint64_t findORs(uint64_t start, uint32_t maxCheck) {
    uint64_t i;
    int c = 0;
    uint8_t lb = 0x01;

    for (i = start; i < fileSize; i++) {
        if (fileData[i] == 0xF0 && fileData[i+1] == 0x80 && fileData[i+7] == lb) {
            orPos[c++] = i;
            i += 7;
            lb <<= 1;
        }
        if (c == 4) {
            break;
        }
        if (--maxCheck == 0) {
            break;
        }
    }
    return c;
}

/*****************************************************************************/
void patchBootParams() {
    uint64_t addr, pos;
    uint64_t newPtrOffset, ptrOffset;
    int n;

    printf("Patching boot params.\n");
    //The function will reside in init code part. We don't care we may potentially search beyond as we expect it to be found
    while (initTextOffs < fileSize) {
        addr = findPUSH_R12_R15_SEQ(initTextOffs);
        if (addr == -1)
            break; //no more "functions" left
        printf("\rAnalyzing f() candidate @ %lX, PUSH @ %lX", initTextOffs, addr);
        //we found something looking like PUSH R12-R15, now find the ORs
        n = findORs(initTextOffs, 1024);
        if (n != 4) {
            //We can always move forward by the function token length (obvious) but if we couldn't find any LOCK-OR tokens
            // we can skip the whole look ahead distance. We CANNOT do that if we found even a single token because the next one
            // might have been just after the look ahead distance
            initTextOffs += 2;
            if (n == 0) {
                initTextOffs += 1024;
            }
            continue; //Continue the main search loop to find next function candidate
        }
        //We found LOCK(); OR ptr sequences so we can print some logs and collect ptrs (as this is quite expensive)
        printf("\n[?] Found possible f() @ %lX\n", initTextOffs);
        ptrOffset=0;
        int ec = 0;
        for (n = 0; n < 4; n++) {
            //data will have the following bytes:
            // [0-LOCK()] [1-OR()] [2-BYTE-PTR] [3-OFFS-b3] [4-OFFS-b2] [5-OFFS-b1] [6-OFFS-b1] [7-NUMBER]
            pos = orPos[n];
            //how far it "jumps"
            newPtrOffset = pos + (fileData[pos+6] << 24 | fileData[pos+5] << 16 | fileData[pos+4] << 8 | fileData[pos+3]);
            if (ptrOffset == 0) {
                ptrOffset = newPtrOffset;
                ++ec;
            } else if (ptrOffset == newPtrOffset) {
                ++ec;
            }
            printf("\t[+] Found LOCK-OR#%d sequence @ %lX => %02X %02X %02X %02X %02X %02X %02X %02X [RIP+%lX]\n",
              n, pos, fileData[pos], fileData[pos+1], fileData[pos+2], fileData[pos+3], fileData[pos+4],
              fileData[pos+5], fileData[pos+6], fileData[pos+7], newPtrOffset);
        }
        if (ec != 4) {
            printf("\t[-] LOCK-OR PTR offset mismatch - %d/4 matched\n", ec);
            //If the pointer checking failed we can at least move beyond the last LOCK-OR found as we know there's no valid
            // sequence of LOCK-ORs there
            initTextOffs = orPos[3];
            continue;
        }
        printf("\t[+] All %d LOCK-OR PTR offsets equal - match found!\n", ec);
        break;
    }
    if (addr == -1) {
        errorMsg("\nFailed to find matching sequences\n");
    } else {
        //Patch offsets
        for (n = 0; n < 4; n++) {
            //The offset will point at LOCK(), we need to change the OR (0x80 0x0d) to AND (0x80 0x25) so the two bytes after
            pos = orPos[n] + 2;
            printf("Patching OR to AND @ %lX\n", pos);
            fileData[pos] = 0x25;
        }
    }
}

/*****************************************************************************/
uint32_t changeEndian(uint32_t num) {
    return ((num>>24)&0xff)       | // move byte 3 to byte 0
           ((num<<8)&0xff0000)    | // move byte 1 to byte 2
           ((num>>8)&0xff00)      | // move byte 2 to byte 1
           ((num<<24)&0xff000000);  // move byte 0 to byte 3
}

/*****************************************************************************/
uint64_t findSeq(const char* seq, int len, uint32_t pos, int dir, uint64_t max) {
    uint64_t i = pos;

    do {
        if (memcmp((const char*)fileData+i, seq, len) == 0) {
            return i;
        }
        i += dir;
        --max;
    } while(i > 0 && i < fileSize && max > 0);
    return -1;
}

/*****************************************************************************/
void patchRamdiskCheck() {
    uint64_t pos, errPrintAddr;
    uint64_t printkPos, testPos, jzPos;
    const char str[] = "3ramdisk corrupt";

    printf("Patching ramdisk check.\n");
    for (pos = rodataOffs; pos < fileSize; pos++) {
        if (memcmp(str, (const char*)(fileData + pos), 16) == 0) {
            pos -= rodataOffs;
            break;
        }
    }
    errPrintAddr = rodataAddr + pos - 1;
    printf("LE arg addr: %08lX\n", errPrintAddr);
    printkPos = findSeq((const char*)&errPrintAddr, 4, 0, DIR_FWD, -1);
    if (printkPos == -1) {
        errorMsg("printk pos not found!\n");
    }
    //double check if it's a MOV reg,VAL (where reg is EAX/ECX/EDX/EBX/ESP/EBP/ESI/EDI)
    printkPos -= 3;
    if (memcmp((const char*)fileData+printkPos, "\x48\xc7", 2) != 0) {
        errorMsg("Expected MOV=>reg before printk error, got %02X %02X\n", fileData[printkPos], fileData[printkPos+1]);
    }
    if (fileData[printkPos+2] < 0xC0 || fileData[printkPos+2] > 0xC7) {
        errorMsg("Expected MOV w/reg operand [C0-C7], got %02X\n", fileData[printkPos+2]);
    }
    printf("Found printk MOV @ %08lX\n", printkPos);

    //now we should seek a reasonable amount (say, up to 32 bytes) for a sequence of CALL x => TEST EAX,EAX => JZ
    testPos = findSeq("\x85\xc0", 2, printkPos, DIR_RWD, 32);
    if (testPos == -1) {
        errorMsg("Failed to find TEST eax,eax\n");
    }
    printf("Found TEST eax,eax @ %08lX\n", testPos);
    jzPos = testPos + 2;
    if (fileData[jzPos] != 0x74) {
        errorMsg("Failed to find JZ\n");
    }
    printf("OK - patching %02X%02X (JZ) to %02X%02X (JMP) @ %08lX\n", 
      fileData[jzPos], fileData[jzPos+1], 0xEB, fileData[jzPos+1], jzPos);
    fileData[jzPos] = 0xEB;
}

/*****************************************************************************/
void patchCmosWrite() {
    uint64_t pos, errPrintAddr;
    uint64_t pr_errPos, testPos, callPos;
    const char str[] = "3smpboot: %s: this boot have memory training";

    printf("Patching call to rtc_cmos_write.\n");
    for (pos = rodataOffs; pos < fileSize; pos++) {
        if (memcmp(str, (const char*)(fileData + pos), 16) == 0) {
            pos -= rodataOffs;
            break;
        }
    }
    errPrintAddr = rodataAddr + pos - 1;
    printf("LE arg addr: %08lX\n", errPrintAddr);
    pr_errPos = findSeq((const char*)&errPrintAddr, 4, 0, DIR_FWD, -1);
    if (pr_errPos == -1) {
        printf("pr_err pos not found - ignoring.\n");      // Some kernels do not have the call, exit without error
        return;
    }
    //double check if it's a MOV reg,VAL (where reg is EAX/ECX/EDX/EBX/ESP/EBP/ESI/EDI)
    pr_errPos -= 3;
    if (memcmp((const char*)fileData+pr_errPos, "\x48\xc7", 2) != 0) {
        errorMsg("Expected MOV=>reg before pr_err error, got %02X %02X\n", fileData[pr_errPos], fileData[pr_errPos+1]);
    }
    if (fileData[pr_errPos+2] < 0xC0 || fileData[pr_errPos+2] > 0xC7) {
        errorMsg("Expected MOV w/reg operand [C0-C7], got %02X\n", fileData[pr_errPos+2]);
    }
    printf("Found pr_err MOV @ %08lX\n", pr_errPos);

    // now we should seek a reasonable amount (say, up to 64 bytes) for a sequence of 
    // MOV ESI, 0x48 => MOV EDI, 0xFF => MOV EBX, EAX
    testPos = findSeq("\xBE\x48\x00\x00\x00\xBF\xFF\x00\x00\x00\x89\xC3", 12, pr_errPos, DIR_RWD, 64);
    if (testPos == -1) {
        printf("Failed to find MOV ESI, 0x48 => MOV EDI, 0xFF => MOV EBX, EAX\n");
        return;
    }
    printf("Found MOV ESI, 0x48 => MOV EDI, 0xFF => MOV EBX, EAX @ %08lX\n", testPos);
    callPos = testPos + 12;
    if (fileData[callPos] != 0xE8) {
        errorMsg("Failed to find CALL\n");
    }
    printf("OK - patching %02X (CALL) to 0x90.. (NOPs) @ %08lX\n", 
      fileData[callPos], callPos);
    for(uint64_t i = 0; i < 5; i++)
      fileData[callPos+i] = 0x90;
}

/*****************************************************************************/
int main(int argc, char *argv[]) {
    struct stat fileInf;
    Elf_Scn *section;
    GElf_Shdr sectionHeader;
    char *sectionName;
    char *fileIn = NULL, *fileOut = NULL;
    int onlyBoot = 0, onlyRD = 0, onlyCMOS = 0, c;

    if (argc < 3) {
        errorMsg("Use: kpatch (option) <vmlinux> <output>\nOptions:\n -b  Only bootparams\n -r  Only ramdisk\n -c  Only CMOS");
    }
    c = 1;
    while (c < argc) {
      if (strcmp(argv[c], "-b") == 0) {
        onlyBoot = 1;
      } else if (strcmp(argv[c], "-r") == 0) {
        onlyRD = 1;
      } else if (strcmp(argv[c], "-c") == 0) {
        onlyCMOS = 1;
      } else if (fileIn == NULL) {
        fileIn = argv[c];
      } else {
        fileOut = argv[c];
        break;
      }
      ++c;
    }
    if (NULL == fileIn) {
        errorMsg("Please give a input filename");
    }
    if (NULL == fileOut) {
        errorMsg("Please give a output filename");
    }

    if (elf_version(EV_CURRENT) == EV_NONE)
        elfErrno();

    if ((fd = open(fileIn, O_RDONLY)) == -1)
        errorNum();

    if ((elfHandle = elf_begin(fd, ELF_C_READ, NULL)) == NULL)
        elfErrno();
    if (gelf_getehdr(elfHandle, &elfExecHeader) == NULL)
        elfErrno();

    switch(elf_kind(elfHandle)) {
        case ELF_K_NUM:
        case ELF_K_NONE:
            errorMsg("file type unknown\n");
            break;
        case ELF_K_COFF:
            errorMsg("COFF binaries not supported\n");
            break;
        case ELF_K_AR:
            errorMsg("AR archives not supported\n");
            break;
        case ELF_K_ELF:
            break;
    }

    section = NULL;
    while ((section = elf_nextscn(elfHandle, section)) != NULL) {
        if (gelf_getshdr(section, &sectionHeader) != &sectionHeader)
            elfErrno();
        if ((sectionName = elf_strptr(elfHandle, elfExecHeader.e_shstrndx, sectionHeader.sh_name)) == NULL)
            elfErrno();
        if (strcmp(sectionName, ".init.text") == 0) {
            initTextOffs = sectionHeader.sh_offset;
        } else if (strcmp(sectionName, ".rodata") == 0) {
            rodataAddr = sectionHeader.sh_addr & 0xFFFFFFFF;
            rodataOffs = sectionHeader.sh_offset;
        }
    }
    elfErrno(); /* If there isn't elf_errno set, nothing will happend. */
    elf_end(elfHandle);

    if (fstat(fd, &fileInf) == -1)
        errorNum();

    fileSize = fileInf.st_size;
    fileData = malloc(fileSize);
    if (fileSize != read(fd, fileData, fileSize)) {
        errorNum();
    }
    close(fd);

    printf("Found .init.text offset @ %lX\n", initTextOffs);
    printf("Found .rodata address @ %lX\n", rodataAddr);
    printf("Found .rodata offset @ %lX\n", rodataOffs);
    if (onlyBoot == 0 && onlyCMOS == 0 && onlyRD == 0) {
        patchBootParams();
        patchRamdiskCheck();
        patchCmosWrite();
    } else {
        if (onlyBoot == 1) {
            patchBootParams();
        }
        if (onlyRD == 1) {
            patchRamdiskCheck();
        }
        if (onlyCMOS == 1) {
            patchCmosWrite();
        }
    }
    if ((fd = open(fileOut, O_WRONLY | O_CREAT, 0644)) == -1) {
        errorNum();
    }
    if (fileSize != write(fd, fileData, fileSize)) {
        errorNum();
    }
    close(fd);
    printf("Finish!\n");
    return 0;
}

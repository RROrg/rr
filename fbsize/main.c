/*
 * Copyright (C) 2022 Ing <https://github.com/wjz304>
 *
 * This is free software, licensed under the MIT License.
 * See /LICENSE for more information.
 *
 */

#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <getopt.h>

#define VERSION "1.0"

int main(int argc, char *argv[])
{
    int c;

    while (1)
    {
        int option_index = 0;
        static struct option long_options[] = {
            {"resolution", required_argument, 0, 'r'},
            {"buffer", required_argument, 0, 'b'},
            {"offset", required_argument, 0, 'o'},
            {"screen", required_argument, 0, 's'},
            {"help", no_argument, 0, 'h'},
            {0, 0, 0, 0}};

        c = getopt_long(argc, argv, "r:b:o:s:h", long_options, &option_index);
        if (c == -1)
            break;

        switch (c)
        {
        case 'r':
        case 'b':
        case 'o':
        case 's':
            int fbfd = 0;
            struct fb_var_screeninfo var_info;

            // 打开设备文件
            fbfd = open(optarg, O_RDWR);
            if (fbfd == -1)
            {
                perror("Error: cannot open framebuffer device");
                return 1;
            }

            // 获取屏幕参数
            if (ioctl(fbfd, FBIOGET_VSCREENINFO, &var_info) == -1)
            {
                perror("Error reading variable information");
                return 1;
            }

            if (c == 'r')
            {
                printf("%dx%d\n", var_info.xres, var_info.yres);
            }
            else if (c == 'b')
            {
                printf("%dx%d\n", var_info.xres_virtual, var_info.yres_virtual);
            }
            else if (c == 'o')
            {
                printf("%dx%d\n", var_info.xoffset, var_info.yoffset);
            }
            else if (c == 's')
            {
                printf("%dx%d\n", var_info.height, var_info.width);
            }

            // 关闭设备文件
            close(fbfd);
            break;
        case 'h':
        case '?':
            printf("Usage: %s [options] <framebuffer_device>\n", argv[0]);
            printf("Version: %s\n", VERSION);
            printf("Options:\n");
            printf("  -r, --resolution   Display the resolution of the screen\n");
            printf("  -b, --buffer       Display the resolution of the framebuffer\n");
            printf("  -o, --offset       Display the offset of the screen\n");
            printf("  -s, --screen       Display the size of the screen\n");
            printf("  -h, --help         Display this help message\n");
            return 0;
        default:
            return 1;
        }
    }

    return 0;
}
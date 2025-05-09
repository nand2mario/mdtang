// Simple firmware for Tang cores
// nand2mario, 2024.1
//
// Needs xpack-gcc risc-v gcc: https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/
// Use build.bat to build. Then burn firmware.bin to SPI flash address 0x500000 with Gowin programmer.

#include <stdbool.h>
#include "picorv32.h"
#include "fatfs/ff.h"
#include "firmware.h"

uint32_t CORE_ID;
#define CORE_NES 1
#define CORE_SNES 2
#define CORE_GBA 3
#define CORE_MD 4

#define OPTION_FILE "/snestang.ini"
#define OPTION_INVALID 2

#define OPTION_OSD_KEY_SELECT_START 1
#define OPTION_OSD_KEY_SELECT_RIGHT 2

// SNES BSRAM is mapped at address 7MB 
volatile uint8_t *SNES_BSRAM = (volatile uint8_t *)0x07000000;

int option_osd_key = OPTION_OSD_KEY_SELECT_RIGHT;
#define OSD_KEY_CODE (option_osd_key == OPTION_OSD_KEY_SELECT_START ? 0xC : 0x84)
bool option_backup_bsram = false;

bool core_running;

int core_backup_size;
bool core_backup_valid;		// whether it is okay to save
char core_backup_name[256];
uint16_t snes_bsram_crc16;
uint32_t core_backup_time;

const int GBA_BACKUP_NONE = 0;
const int GBA_BACKUP_FLASH512K = 1;
const int GBA_BACKUP_FLASH1M = 2;
const int GBA_BACKUP_SRAM = 3;
const int GBA_BACKUP_EEPROM = 4;     // EEPROM with size auto-detected
int gba_backup_type;       // 0: none, 1: auto detected from rom content
bool gba_bios_loaded;
bool gba_missing_bios_warned;

char load_fname[1024];
char load_buf[1024];

// return 0: success, 1: no option file found, 2: option file corrupt
int load_option()  {
    FIL f;
    int r = 0;
    char buf[1024];
    char *line, *key, *value;
    if (f_open(&f, OPTION_FILE, FA_READ))
        return 1;
    // XXX: handle escapes and quotes
    while (f_gets(buf, 1024, &f)) {
        line = trimwhitespace(buf);
        if (line[0] == '\0' || line[0] == '[' || line[0] == ';' || line[0] == '#')
            continue;
        // find '='
        char *s = strchr(line, '=');
        if (!s) {
            r = OPTION_INVALID;
            goto load_option_close;
        }
        *s='\0';
        key = trimwhitespace(line);
        value = trimwhitespace(s+1);
        // status("");
        uart_printf("key=%s, value=%s\n", key, value);
        // message("see below",1);

        // now handle all key-value pairs
        if (strcmp(key, "osd_key") == 0) {
            option_osd_key = atoi(value);
            if (option_osd_key <= 0) {
                r = OPTION_INVALID;
                goto load_option_close;
            }
        } else if (strcmp(key, "backup_bsram") == 0) {
            if (strcasecmp(value, "true") == 0)
                option_backup_bsram = true;
            else
                option_backup_bsram = false;
        } else {
            // just ignore unknown keys
        }
    }

load_option_close:
    f_close(&f);
    return r;
}


// return 0: success, 1: cannot save
int save_option() {
    FIL f;
    if (f_open(&f, OPTION_FILE, FA_READ | FA_WRITE | FA_CREATE_ALWAYS)) {
        message("f_open failed",1);
        return 1;
    }
    if (f_puts("osd_key=", &f) < 0) {
        message("f_puts failed",1);
        goto save_options_close;
    }
    if (option_osd_key == OPTION_OSD_KEY_SELECT_START)
        f_puts("1\n", &f);
    else
        f_puts("2\n", &f);
    
    f_puts("backup_bsram=", &f);
    if (option_backup_bsram)
        f_puts("true\n", &f);
    else
        f_puts("false\n", &f);
        
save_options_close:
    f_close(&f);
    // hide snestang.ini in dir list
    f_chmod(OPTION_FILE, AM_HID, AM_HID);
    return 0;
}

void status(char *msg) {
    cursor(0, 27);
    for (int i = 0; i < 32; i++)
        putchar(' ');
    cursor(2, 27);
    print(msg);
}

// show a pop-up message, press any key to discard (caller needs to redraw screen)
// msg: could be multi-line (separate with \n), max 10 lines
// center: whether to center the text
void message(char *msg, int center) {
    // count number of lines and max width
    int w[10], lines=10, maxw = 0;
    int len = strlen(msg);
    char *end = msg + len;
    char *sol = msg;
    for (int i = 0; i < 10; i++) {
        char *eol = strchr(sol, '\n');
        if (eol) { // found \n
            w[i] = min(eol - sol, 26);
            maxw = max(w[i], maxw);
            sol = eol+1;
        } else {
            w[i] = min(end - sol, 26);
            maxw = max(w[i], maxw);
            lines = i+1;
            break;
        }		
    }
    // status("");
    // printf("w=%d, lines=%d", maxw, lines);
    // draw a box 
    int y0 = 14 - ((lines + 2) >> 1);
    int y1 = y0 + lines + 2;
    int x0 = 16 - ((maxw + 2) >> 1);
    int x1 = x0 + maxw + 2;
    for (int y = y0; y < y1; y++)
        for (int x = x0; x < x1; x++) {
            cursor(x, y);
            if ((x == x0 || x == x1-1) && (y == y0 || y == y1-1))
                putchar('+');
            else if (x == x0 || x == x1-1)
                putchar('|');
            else if (y == y0 || y == y1-1)
                putchar('-');
            else
                putchar(' ');
        }
    // print text
    char *s = msg;
    for (int i = 0; i < lines; i++) {
        if (center)
            cursor(16-(w[i]>>1), y0+i+1);
        else
            cursor(x0+1, y0+i+1);
        while (*s != '\n' && *s != '\0') {
            putchar(*s);
            s++;
        }
        s++;
    }
    // wait for a keypress
    delay(300);
    for (;;) {
        int joy1, joy2;
        joy_get(&joy1, &joy2);
           if ((joy1 & 0x1) || (joy1 & 0x100) || (joy2 & 0x1) || (joy2 & 0x100))
               break;
    }
    delay(300);
}


FATFS fs;

#define PAGESIZE 22
#define TOPLINE 2
#define PWD_SIZE 1024

char pwd[PWD_SIZE];		// total path length 1023
// one page of file names to display
char file_names[PAGESIZE][256];
int file_dir[PAGESIZE];
int file_sizes[PAGESIZE];
int file_len;		// number of files on this page

// starting from `start`, load `len` file names into file_names, 
// file_dir. 
// *count is set to number of all valid entries and `file_len` is
// set to valid entries on this page.
// return: 0 if successful
int load_dir(char *dir, int start, int len, int *count) {
    DEBUG("load_dir: %s, start=%d, len=%d\n", dir, start, len);
    int cnt = 0;
    DIR d;
    file_len = 0;
    // initiaze sd again to be sure
    int init_ok = 0;
    for (int i = 0; i <= 10; i++)
        if (sd_init() == 0) {
            init_ok = 1;
            break;
        }
    if (!init_ok) return 99;

    if (f_opendir(&d, dir) != 0) {
        return -1;
    }
    // an entry to return to parent dir or main menu 
    int is_root = dir[1] == '\0';
    if (start == 0 && len > 0) {
        if (is_root) {
            strncpy(file_names[0], "<< Return to main menu", 256);
            file_dir[0] = 0;
        } else {
            strncpy(file_names[0], "..", 256);
            file_dir[0] = 1;
        }
        file_len++;
    }
    cnt++;

    // generate all file entries
    FILINFO fno;
    while (f_readdir(&d, &fno) == FR_OK) {
        if (fno.fname[0] == 0)
            break;
        if ((fno.fattrib & AM_HID) || (fno.fattrib & AM_SYS))
             // skip hidden and system files
            continue;
        if (cnt >= start && file_len < len) {
            strncpy(file_names[file_len], fno.fname, 256);
            file_dir[file_len] = fno.fattrib & AM_DIR;
            file_sizes[file_len] = fno.fsize;
            file_len++;
            DEBUG("%s\n", fno.fname);
        }
        cnt++;
    }
    f_closedir(&d);
    *count = cnt;
    DEBUG("load_dir: count=%d\n", cnt);
    return 0;
}

// return 0: user chose a ROM (*choice), 1: no choice made, -1: error
// file chosen: pwd / file_name[*choice]
int menu_loadrom(int *choice) {
    int page = 0, pages, total;
    int active = 0;
    pwd[0] = '/';
    pwd[1] = '\0';
    while (1) {
        clear();
        int r = load_dir(pwd, page*PAGESIZE, PAGESIZE, &total);
        if (r == 0) {
            pages = (total+PAGESIZE-1) / PAGESIZE;
            status("Page ");
            printf("%d/%d", page+1, pages);
            if (active > file_len-1)
                active = file_len-1;
            for (int i = 0; i < PAGESIZE; i++) {
                int idx = page*PAGESIZE + i;
                cursor(2, i+TOPLINE);
                if (idx < total) {
                    print(file_names[i]);
                    if (idx != 0 && file_dir[i])
                        print("/");
                }
            }
            delay(300);
            while (1) {
                int r = joy_choice(TOPLINE, file_len, &active, OSD_KEY_CODE);
                if (r == 1) {
                    if (strcmp(pwd, "/") == 0 && page == 0 && active == 0) {
                        // return to main menu
                        return 1;
                    } else if (file_dir[active]) {
                        if (file_names[active][0] == '.' && file_names[active][1] == '.') {
                            // return to parent dir
                            // message(file_names[active], 1);
                            char *slash = strrchr(pwd, '/');
                            if (slash)
                                *slash = '\0';
                        } else {								// enter sub dir
                            strncat(pwd, "/", PWD_SIZE);
                            strncat(pwd, file_names[active], PWD_SIZE);
                        }
                        active = 0;
                        page = 0;
                        break;
                    } else {
                        // actually load a ROM
                        *choice = active;
                        int res;
                        switch (CORE_ID) {
                            case CORE_NES:
                                res = loadnes(active);
                                break;
                            case CORE_SNES:
                                res = loadsnes(active);
                                break;
                            case CORE_GBA:
                                res = loadgba(active);
                                break;
                            case CORE_MD:
                                res = loadmd(active);
                                break;
                            default:
                                res = -1;
                        }
                        if (res != 0) {
                            message("Cannot load rom",1);
                            break;
                        }
                    }
                }
                if (r == 2 && page < pages-1) {
                    page++;
                    break;
                } else if (r == 3 && page > 0) {
                    page--;
                    break;
                }
            }
        } else {
            status("Error opening director");
            printf(" %d", r);
            return -1;
        }
    }
}

uint8_t corebuf[256];
uint32_t t_ready, t_flash, t_file, t_parse;

void write_flash(uint8_t *corebuf, uint32_t addr, int cnt) {
    uint32_t start = cycle_counter();
    // uart_printf("Writing %d bytes at %x\n", cnt, addr);
    if ((addr & 0xfff) == 0) {	// whole 4KB, erase sector first
        uint32_t t = cycle_counter();
        spiflash_ready();
        t_ready += cycle_counter() - t;
        spiflash_sector_erase(addr);
        // uart_printf("Sector erased\n");
    }
    uint32_t t = cycle_counter();
    spiflash_ready();
    t_ready += cycle_counter() - t;
    spiflash_page_program(addr, corebuf);
    if ((addr & 0xfff) == 0) {
        status("");
        printf("%d KB written", addr >> 10);
    }
    t_flash += cycle_counter() - start;
    spiflash_ready();
}

// return true: verify OK
bool verify_flash(uint8_t *corebuf, uint32_t addr, int cnt) {
    // uart_printf("Verifying %d bytes at %x\n", cnt, addr);
    uint8_t buf[256];
    // uart_print("Reading flash\n");
    spiflash_read(addr, buf, 256);
    // uart_print("Done with flash read\n");
    for (int j = 0; j < cnt; j++) {
        if (buf[j] != corebuf[j]) {
            uart_printf("Verify error at %x: %d != %d. Data read:\n", addr+j, buf[j], corebuf[j]);
            for (int i = 0; i < 256; i++) {
                if (i > 0 && i % 16 == 0)
                    uart_print("\n");
                uart_print_hex_digits(buf[i], 2);
                uart_print(" ");
            }
            uart_print("\n");
            return false;
        }
    }
    if ((addr & 0xfff) == 0) {
        status("");
        printf("%d KB verified", addr >> 10);
    }
    return true;
}

static unsigned int load_buf_off;  // next available pos in load_buf
static unsigned int load_buf_len;  // length of data in load_buf

// load a line into buf (max length *len), *len is updated to actual length of string
// this uses load_buf[] internally
void read_line(FIL *fp, char *buf, int *len) {
    int i = 0;
    bool done = false;
    while (!done) {
        for (; !done && i + 1 < *len && load_buf_off < load_buf_len; i++, load_buf_off++) {
            buf[i] = load_buf[load_buf_off];
            if (load_buf[load_buf_off] == '\n')
                done = true;
        }
        if (i == *len)
            done = true;
        if (!done) {
            // load more data
            load_buf_off = 0;
            if (f_eof(fp))
                break;
            f_read(fp, load_buf, 1024, &load_buf_len);
        }
    }
    buf[i] = 0;
    *len = i;
}

static char line_buf[4096];         // .fs file has max 3.5K lines

void load_core(char *fname, int verify) {
    FIL f;
    int binfile = strcasestr(fname, ".bin") != NULL;      // 1: bin        
    t_ready = 0; t_flash = 0, t_file = 0; t_parse = 0;
    if (binfile)
        uart_printf("Loading bin file: %s\n", fname);
    else
        uart_printf("Loading fs file: %s\n", fname);
    if (verify && !binfile) {
        message("Verify only supported for .bin files", 1);
        return;
    }

    if (f_open(&f, fname, FA_READ) != FR_OK) {
        message("Cannot open core file", 1);
        return;
    }
    int addr = 0;
    char *s = load_buf;
    unsigned int cnt = 0;
    while (!f_eof(&f) && (binfile || addr < 32*1024)) { // write only 32KB for .fs
        if (binfile) {
            // uart_print("Checking cycles\n");
            uint32_t t = cycle_counter();
            // uart_print("Reading file\n");
            f_read(&f, corebuf, 256, &cnt);
            t_file += cycle_counter() - t;
            if (verify) {
                if (!verify_flash(corebuf, addr, cnt))
                    return;
            } else
                write_flash(corebuf, addr, cnt);
            addr += cnt;
            cnt = 0;
        } else {        // parse .fs file
            uint32_t t = cycle_counter();
            if (f_eof(&f)) continue;
            int len = 4096;
            read_line(&f, line_buf, &len);
            // message(line_buf, 0);
            t_file += cycle_counter() - t;
            if (s[0] == '/' && s[1] == '/') {
                // comment, skip the whole line
                continue;
            }
            for (int i = 0; i+8 <= len; i+=8) {	// add a byte to buf
                uint32_t t2 = cycle_counter();
                if (s[i] > '1' || s[i] < '0') break;
                uint8_t b = ((s[i]-'0') << 7) + ((s[i+1]-'0') << 6) +
                        ((s[i+2]-'0') << 5) + ((s[i+3]-'0') << 4) +
                        ((s[i+4]-'0') << 3) + ((s[i+5]-'0') << 2) +
                        ((s[i+6]-'0') << 1) + (s[i+7]-'0');
                corebuf[cnt] = b;
                if (cnt < 16) {
                    char ss[9];
                    strncpy(ss, s+i, 9);
                    uart_printf("[%s]=", ss);
                    uart_print_hex_digits(b, 2);
                    uart_print(" ");
                }
                cnt++;
                t_parse += cycle_counter() - t2;
                if (cnt == 256) {				// write a page
                    uart_printf("Writing at %x:", addr);
                    for (int j = 0; j < 16; j++) {
                        uart_print_hex_digits(corebuf[j], 2);
                        uart_print(" ");
                    }
                    uart_print("\n");
                    write_flash(corebuf, addr, cnt);
                    addr += cnt;
                    cnt = 0;
                }
            }
        }
    }
    // write remaining data in buffer
    if (cnt > 0) {
        write_flash(corebuf, addr, cnt);
        addr += cnt;
    }
    spiflash_write_disable();
    f_close(&f);

    const uint32_t MS = 21500;
    uart_printf("File read cycles: %d, parse cycles: %d, flash total cycles: %d, flash wait cycles: %d\n", t_file, t_parse, t_flash, t_ready);
    uart_printf("File read time: %d ms, parse time: %d ms, flash total time: %d ms, flash wait time: %d ms\n", t_file / MS, t_parse / MS, t_flash / MS, t_ready / MS);
    if (verify)
        message("Core matches", 1);
    else
        message("Core ready. Pls reboot", 1);
}

void menu_select_core(int verify) {
    int total, choice = 0, draw=1;
    int r = load_dir("/cores", 0, PAGESIZE, &total);
    if (r != 0) {
        clear();
        message("Need .bin in /cores", 1);
        return;
    }
    delay(300);

    for (;;) {
        if (draw) {
            clear();
            cursor(2, 2);
            print("<< Return to main menu");        // this replaces ".."
            if (total > PAGESIZE) total = PAGESIZE;
            for (int i = 1; i < total; i++) {
                cursor(2, i+2);
                print(file_names[i]);
            }
            draw = 0;
        }
        // DEBUG("Calling joy_chocie\n");
        if (joy_choice(2, total, &choice, OSD_KEY_CODE) == 1) {
            if (choice == 0)
                return;
            else {
                char *p;
                // p = strcasestr(file_names[choice], ".fs");
                // if (p == NULL)
                p = strcasestr(file_names[choice], ".bin");
                if (p == NULL) {
                    message("Only .bin supported", 1);
                    draw = 1;
                    continue;
                }
                
                // load core
                strncpy(load_fname, "/cores/", 1024);
                strncat(load_fname, file_names[choice], 1024);
                load_core(load_fname, verify);
                return;
            }
        }
        // DEBUG("Done with joy_chocie\n");
    }
}

void _menu_select_core() {
    uint8_t buf[256];
    uart_printf("begin select_core\n");
    spiflash_read(0*1024*1024, buf, 256);
    for (int i = 0; i < 256; i++) {
        if (i > 0 && i % 16 == 0)
            uart_printf("\n");
        uart_print_hex_digits(buf[i], 2);
        uart_print(" ");
    }
    uart_printf("\n");
    
    status("Check UART for log");
    uart_printf("end select_core\n");
}

void menu_options() {
    int choice = 0;
    uart_print("options\n");
    while (1) {
        clear();
        cursor(8, 10);
        print("--- Options ---");

        cursor(2, 12);
        print("<< Return to main menu");
        cursor(2, 14);
        print("OSD hot key:");
        cursor(16, 14);
        if (option_osd_key == OPTION_OSD_KEY_SELECT_START)
            print("SELECT&START");
        else
            print("SELECT&RIGHT");
        cursor(2, 15);
        print("Save to SD:");
        cursor(16, 15);
        if (option_backup_bsram)
            print("Yes");
        else
            print("No");

        delay(300);

        for (;;) {
            if (joy_choice(12, 4, &choice, OSD_KEY_CODE) == 1) {
                if (choice == 0) {
                    return;
                } else if (choice == 1) {
                    // nothing
                } else {
                    if (choice == 2) {
                        if (option_osd_key == OPTION_OSD_KEY_SELECT_START)
                            option_osd_key = OPTION_OSD_KEY_SELECT_RIGHT;
                        else
                            option_osd_key = OPTION_OSD_KEY_SELECT_START;
                    } else if (choice == 3) {
                        option_backup_bsram = !option_backup_bsram;
                    }
                    status("Saving options...");
                    if (save_option()) {
                        message("Cannot save options to SD",1);
                        break;
                    }
                    break;	// redraw UI
                }
            }
        }
    }
}

int in_game;

// return 0 if snes header is successfully parsed at off
// typ 0: LoROM, 1: HiROM, 2: ExHiROM
int parse_snes_header(FIL *fp, int pos, int file_size, int typ, char *hdr,
                      int *map_ctrl, int *rom_type_header, int *rom_size,
                      int *ram_size, int *company) {
    unsigned int br;
    if (f_lseek(fp, pos))
        return 1;
    f_read(fp, hdr, 64, &br);
    if (br != 64) return 1;
    int mc = hdr[21];
    int rom = hdr[23];
    int ram = hdr[24];
    int checksum = (hdr[28] << 8) + hdr[29];
    int checksum_compliment = (hdr[30] << 8) + hdr[31];
    int reset = (hdr[61] << 8) + hdr[60];
    int size2 = 1024 << rom;

    status("");
    printf("size=%d", size2);

    // calc heuristics score
    int score = 0;		
    if (size2 >= file_size) score++;
    if (rom == 1) score++;
    if (checksum + checksum_compliment == 0xffff) score++;
    int all_ascii = 1;
    for (int i = 0; i < 21; i++)
        if (hdr[i] < 32 || hdr[i] > 127)
            all_ascii = 0;
    score += all_ascii;

    DEBUG("pos=%x, type=%d, map_ctrl=%d, rom=%d, ram=%d, checksum=%x, checksum_comp=%x, reset=%x, score=%d\n", 
            pos, typ, mc, rom, ram, checksum, checksum_compliment, reset, score);

    if (rom < 14 && ram <= 7 && score >= 1 && 
        reset >= 0x8000 &&				// reset vector position correct
       ((typ == 0 && (mc & 3) == 0) || 	// normal LoROM
        (typ == 0 && mc == 0x53)    ||	// contra 3 has 0x53 and LoROM
        (typ == 1 && (mc & 3) == 1) ||	// HiROM
        (typ == 2 && (mc & 3) == 2))) {	// ExHiROM
        *map_ctrl = mc;
        *rom_type_header = hdr[22];
        *rom_size = rom;
        *ram_size = ram;
        *company = hdr[26];
        return 0;
    }
    return 1;
}

// actually load a rom file. if bsram backup is needed, also loads the backup.
// return 0 if successful
int loadsnes(int rom) {
    FIL f;
    int r = 1;
    strncpy(load_fname, pwd, 1024);
    strncat(load_fname, "/", 1024);
    strncat(load_fname, file_names[rom], 1024);

    // check extension .sfc or .smc
    char *p = strcasestr(file_names[rom], ".sfc");
    if (p == NULL)
        p = strcasestr(file_names[rom], ".smc");
    if (p == NULL) {
        status("Only .smc or .sfc supported");
        goto loadsnes_end;
    }
    // core_backup_name = <base>.srm
    int base_len = p-file_names[rom];
    strncpy(core_backup_name, file_names[rom], base_len);
    strcpy(core_backup_name+base_len, ".srm");

    // initiaze sd again to be sure
    if (sd_init() != 0) return 99;

    r = f_open(&f, load_fname, FA_READ);
    if (r) {
        status("Cannot open file");
        goto loadsnes_end;
    }
    unsigned int br, total = 0;
    int size = file_sizes[rom];
    int map_ctrl, rom_type_header, rom_size, ram_size, company;
    // parse SNES header from ROM file
    int off = size & 0x3ff;		// rom header (0 or 512)
    int header_pos;
    DEBUG("off=%d\n", off);
    
    header_pos = 0x7fc0 + off;
    if (parse_snes_header(&f, header_pos, size-off, 0, load_buf, &map_ctrl, &rom_type_header, &rom_size, &ram_size, &company)) {
        header_pos = 0xffc0 + off;
        if (parse_snes_header(&f, header_pos, size-off, 1, load_buf, &map_ctrl, &rom_type_header, &rom_size, &ram_size, &company)) {
            header_pos = 0x40ffc0 + off;
            if (parse_snes_header(&f, header_pos, size-off, 2, load_buf, &map_ctrl, &rom_type_header, &rom_size, &ram_size, &company)) {
                status("Not a SNES ROM file");
                delay(200);
                goto loadsnes_close_file;
            }
        }
    }

    // load actual ROM
    core_ctrl(1);		// enable game loading, this resets SNES
    core_running = false;

    // Send 64-byte header to snes
    for (int i = 0; i < 64; i += 4) {
        uint32_t *w = (uint32_t *)(load_buf + i);
        core_data(*w);
    }

    // Send rom content to snes
    if ((r = f_lseek(&f, off)) != FR_OK) {
        status("Seek failure");
        goto loadsnes_snes_end;
    }
    do {
        if ((r = f_read(&f, load_buf, 1024, &br)) != FR_OK)
            break;
        for (int i = 0; i < br; i += 4) {
            uint32_t *w = (uint32_t *)(load_buf + i);
            core_data(*w);				// send actual ROM data
        }
        total += br;
        if ((total & 0xffff) == 0) {	// display progress every 64KB
            status("");
            printf("%d/%dK", total >> 10, size >> 10);
            if ((map_ctrl & 3) == 0)
                print(" Lo");
            else if ((map_ctrl & 3) == 1)
                print(" Hi");
            else if ((map_ctrl & 3) == 2)
                print(" ExHi");
            printf(" ROM=%d RAM=%d", 1 << rom_size, ram_size ? (1 << ram_size) : 0);
        }
    } while (br == 1024);

    // load BSRAM backup
    core_backup_size = ram_size == 0 ? 0 : ((1 << ram_size) << 10);
    if (core_backup_size > 0)
        memset((uint8_t *)0x700000, 0, core_backup_size);		// clear BSRAM
    backup_load(core_backup_name, core_backup_size);

    status("Success");
    core_running = true;

    overlay(0);		// turn off OSD

loadsnes_snes_end:
    core_ctrl(0);	// turn off game loading, this starts SNES
loadsnes_close_file:
    f_close(&f);
loadsnes_end:
    return r;
}

// load a NES rom file.
// return 0 if successful
int loadnes(int rom) {
    FIL f;
    int r = 1;
    strncpy(load_fname, pwd, 1024);
    strncat(load_fname, "/", 1024);
    strncat(load_fname, file_names[rom], 1024);

    DEBUG("loadnes start\n");

    // check extension .sfc or .smc
    char *p = strcasestr(file_names[rom], ".nes");
    if (p == NULL) {
        status("Only .nes supported");
        goto loadnes_end;
    }

    // initiaze sd again to be sure
    if (sd_init() != 0) return 99;

    r = f_open(&f, load_fname, FA_READ);
    if (r) {
        status("Cannot open file");
        goto loadnes_end;
    }
    unsigned int off = 0, br, total = 0;
    unsigned int size = file_sizes[rom];

    // load actual ROM
    core_ctrl(1);		// enable game loading, this resets SNES
    core_running = false;

    // Send rom content to snes
    if ((r = f_lseek(&f, off)) != FR_OK) {
        status("Seek failure");
        goto loadnes_snes_end;
    }
    do {
        if ((r = f_read(&f, load_buf, 1024, &br)) != FR_OK)
            break;
        for (int i = 0; i < br; i += 4) {
            uint32_t *w = (uint32_t *)(load_buf + i);
            core_data(*w);				// send actual ROM data
        }
        total += br;
        if ((total & 0xfff) == 0) {	// display progress every 4KB
            status("");
            printf("%d/%dK", total >> 10, size >> 10);
        }
    } while (br == 1024);

    DEBUG("loadnes: %d bytes\n", total);
    status("Success");
    core_running = true;

    overlay(0);		// turn off OSD

loadnes_snes_end:
    core_ctrl(0);   // turn off game loading, this starts the core
    f_close(&f);
loadnes_end:
    return r;
}

// check if gba_bios.bin is present in the root directory
// if not, warn user, if present, load it
void gba_load_bios() {
    if (gba_bios_loaded | gba_missing_bios_warned) return;

    DEBUG("gba_load_bios start\n");
    FILINFO fno;
    if (f_stat("/gba_bios.bin", &fno) != FR_OK) {
        message( "Cannot find /gba_bios.bin\n"
                 "Using open source BIOS\n"
                 "Expect low compatibility", 1);
        gba_missing_bios_warned = 1;
        return;
    }

    FIL f;
    int r = 1;
    unsigned br;
    if (f_open(&f, "/gba_bios.bin", FA_READ) != FR_OK) {
        message("Cannot open /gba_bios.bin", 1);
        return;
    }
    core_ctrl(4);
    do {
        if ((r = f_read(&f, load_buf, 1024, &br)) != FR_OK)
            break;
        for (int i = 0; i < br; i += 4) {
            uint32_t w = *(uint32_t *)(load_buf + i);
            core_data(w);
        }
    } while (br == 1024);

    f_close(&f);
    gba_bios_loaded = 1;
    DEBUG("gba_load_bios end\n");
}

// load a GBA rom file.
// return 0 if successful
int loadgba(int rom) {
    FIL f;
    int r = 1;
    strncpy(load_fname, pwd, 1024);
    strncat(load_fname, "/", 1024);
    strncat(load_fname, file_names[rom], 1024);

    DEBUG("loadgba start\n");

    // check extension .gba
    char *p = strcasestr(file_names[rom], ".gba");
    if (p == NULL) {
        status("Only .gba supported");
        goto loadgba_end;
    }
    // core_backup_name = <base>.srm
    int base_len = p-file_names[rom];
    strncpy(core_backup_name, file_names[rom], base_len);
    strcpy(core_backup_name+base_len, ".srm");

    // initiaze sd again to be sure
    if (sd_init() != 0) return 99;

    r = f_open(&f, load_fname, FA_READ);
    if (r) {
        status("Cannot open file");
        goto loadgba_end;
    }
    unsigned int off = 0, br, total = 0;
    unsigned int size = file_sizes[rom];

    // load actual ROM
    core_ctrl(1);		// enable game loading, this resets GBA
    core_running = false;

    // Send rom content to gba
    if ((r = f_lseek(&f, off)) != FR_OK) {
        status("Seek failure");
        goto loadgba_close;
    }
    int detect = 0; // 1: past 'EEPR', 2: past 'FLAS', 3: past 'SRAM'
    gba_backup_type = GBA_BACKUP_NONE;
    do {
        if ((r = f_read(&f, load_buf, 1024, &br)) != FR_OK)
            break;
        for (int i = 0; i < br; i += 4) {
            uint32_t w = *(uint32_t *)(load_buf + i);
            core_data(w);				// send actual ROM data

            // detect backup type
            if (gba_backup_type == GBA_BACKUP_NONE) {
                if (detect == 0) {                                      // fast path
                    switch (w) {
                        case 0x52504545:                                // 'EEPR'
                            detect = 1;
                            break;
                        case 0x53414c46:                                // 'FLAS'
                            detect = 2;
                            break;
                        case 0x4d415253:                                // 'SRAM'
                            detect = 3;
                            break;
                    }
                } else {
                    if (detect == 1 && w == 0x565f4d4f) {                // 'OM_V'
                        gba_backup_type = GBA_BACKUP_EEPROM;
                        detect = 0;
                    //     detect = 4;
                    // } else if (detect == 4) {
                    //     if ((w & 0xffff) == 0x3131)                     // '11'    EEPROM_V11*
                    //         gba_backup_type = GBA_BACKUP_EEPROM_4K;
                    //     else                                            // EEPROM_V12*
                    //         gba_backup_type = GBA_BACKUP_EEPROM_64K;
                    //     detect = 0;
                    } else if (detect == 2) {
                        if ( (  w & 0xffffff) == 0x565f48 ||            // 'H_V'
                                w == 0x32313548 )                       // 'H512'
                            gba_backup_type = GBA_BACKUP_FLASH512K;
                        else if (w == 0x5F4D3148)                       // 'H1M_'
                            gba_backup_type = GBA_BACKUP_FLASH1M;
                        detect = 0;
                    } else if (detect == 3) {
                        if ((w & 0xffff) == 0x565F ||                   // '_V'
                             w == 0x565F465F)                           // '_F_V'
                            gba_backup_type = GBA_BACKUP_SRAM;
                        detect = 0;
                    } else
                        detect = 0;
                }
            }
        }

        total += br;
        if ((total & 0xffff) == 0) {	// display progress every 64KB
            status("");
            printf("%d/%dK %s", total >> 10, size >> 10, 
                gba_backup_type == GBA_BACKUP_SRAM ? "SRAM" : 
                gba_backup_type == GBA_BACKUP_FLASH512K ? "FLASH512K" :
                gba_backup_type == GBA_BACKUP_FLASH1M ? "FLASH1M" :
                gba_backup_type == GBA_BACKUP_EEPROM ? "EEPROM" :
                "");
        }
    } while (br == 1024);

    DEBUG("loadgba: %d bytes rom sent.\n", total); 

    core_ctrl(2);
    int cartrom_data = 0;
    if (gba_backup_type == GBA_BACKUP_SRAM || gba_backup_type == GBA_BACKUP_FLASH512K || gba_backup_type == GBA_BACKUP_FLASH1M)
        cartrom_data = 0xffffffff;
    DEBUG("loadgba: initializaing cartram with loader command 2");
    for (int i = 0; i < 128*1024/4; i++)
        core_data(cartrom_data);

    DEBUG("loadgba: set backup type=%d.\n", gba_backup_type); 
    core_ctrl(3);
    core_data(gba_backup_type);

    if (gba_backup_type != GBA_BACKUP_NONE) {
        if (gba_backup_type == GBA_BACKUP_FLASH1M) 
            core_backup_size = 128*1024;
        else if (gba_backup_type == GBA_BACKUP_EEPROM)
            core_backup_size = 8*1024;
        else
            core_backup_size = 64*1024;    
        // DEBUG("loadgba: fill cartram with 0xff, size=%d\n", core_backup_size);
        // memset((uint8_t *)0x700000, 0xff, core_backup_size);		// clear backup memory
        // if (gba_backup_type != GBA_BACKUP_EEPROM) {     // disable EEPROM persistence for now
        DEBUG("loadgba: calling backup_load: %s %d\n", core_backup_name, core_backup_size);
        backup_load(core_backup_name, core_backup_size);
        // }
    }

    gba_load_bios();

    status("Success");
    core_running = true;

    overlay(0);		// turn off OSD

loadgba_close:
    core_ctrl(0);   // turn off game loading, this starts the core
    f_close(&f);
loadgba_end:
    return r;
}


// load a MD/Genesis rom file.
// return 0 if successful
int loadmd(int rom) {
    FIL f;
    int r = 1;
    strncpy(load_fname, pwd, 1024);
    strncat(load_fname, "/", 1024);
    strncat(load_fname, file_names[rom], 1024);

    DEBUG("loadmd start\n");

    // check extension .sfc or .smc
    char *p = strcasestr(file_names[rom], ".bin");
    if (p == NULL) {
        status("Only .bin supported");
        goto loadmd_end;
    }

    // initiaze sd again to be sure
    if (sd_init() != 0) return 99;

    r = f_open(&f, load_fname, FA_READ);
    if (r) {
        status("Cannot open file");
        goto loadmd_end;
    }
    unsigned int off = 0, br, total = 0;
    unsigned int size = file_sizes[rom];

    // load actual ROM
    core_ctrl(1);		// enable game loading, this resets the core
    core_running = false;

    // Send rom content to core
    if ((r = f_lseek(&f, off)) != FR_OK) {
        status("Seek failure");
        goto loadmd_close_file;
    }
    do {
        if ((r = f_read(&f, load_buf, 1024, &br)) != FR_OK)
            break;
        if (br % 4 != 0) {
            uart_printf("WARNING: file size is not multiple of 4, br=%d\n", br);
            break;
        }
        for (int i = 0; i < br; i += 4) {
            uint32_t *w = (uint32_t *)(load_buf + i);
            core_data(*w);				// send actual ROM data
        }
        total += br;
        if ((total & 0xfff) == 0) {	// display progress every 4KB
            status("");
            printf("%d/%dK", total >> 10, size >> 10);
        }
    } while (br == 1024);

    DEBUG("loadmd: %d bytes\n", total);
    status("Success");
    core_running = true;

    overlay(0);		// turn off OSD

loadmd_close_file:
    core_ctrl(0);   // turn off game loading, this starts the core
    f_close(&f);
loadmd_end:
    return r;
}

void backup_load(char *name, int size) {
    core_backup_valid = false;
    if (!option_backup_bsram || size == 0) return;
    char path[266] = "/saves/";
    FILINFO fno;
    uint8_t *bsram = (uint8_t *)0x700000;			// directly read into BSRAM

    if (f_stat(path, &fno) != FR_OK) {
        if (f_mkdir(path) != FR_OK) {
            status("Cannot create /saves");
            uart_printf("Cannot create /saves\n");
            goto backup_load_crc;
        }
    }
    strcat(path, core_backup_name);
    uart_printf("Loading save file from: %s\n", core_backup_name);
    FIL f;
    if (f_open(&f, path, FA_READ) != FR_OK) {
        core_backup_valid = true;					// new save file, mark as valid
        uart_printf("Cannot open save file, assuming new\n");
        goto backup_load_crc;
    }
    uint8_t *p = bsram;	
    unsigned int load = 0;
    while (load < size) {
        unsigned int br;
        if (f_read(&f, p, 1024, &br) != FR_OK || br < 1024) 
            break;
        p += br;
        load += br;
    }
    core_backup_valid = true;
    f_close(&f);
    uart_printf("Save file loaded\n", load);

backup_load_crc:
    if (CORE_ID == CORE_SNES) {
        snes_bsram_crc16 = gen_crc16(bsram, size);
        uart_printf("CRC16: %x\n", snes_bsram_crc16);
    }
    if (CORE_ID == CORE_GBA)
        reg_cartram_dirty = 0;

    return;
}

// return 0: successfully saved, 1: BSRAM unchanged, 2: file write failure
int backup_save(char *name, int size) {
    if (!option_backup_bsram || !core_backup_valid || size == 0) return 1;
    char path[266] = "/saves/";
    FIL f;
    uint8_t *bsram = (uint8_t *)0x700000;		// directly read from BSRAM
    int r = 0;

    uart_printf("backup_save: start\n");

    // first check if BSRAM content is changed since last save
    if (CORE_ID == CORE_SNES) {
        // SNES uses CRC check
        int newcrc = gen_crc16(bsram, size);
        uart_printf("New CRC: %x, size=%d\n", newcrc, size);
        if (newcrc == snes_bsram_crc16) {
            r = 1;
            goto save_end;
        }
        snes_bsram_crc16 = newcrc;
    } else {
        // GBA uses dirty flag
        if (reg_cartram_dirty == 0) {
            r = 1;
            uart_printf("Save data not changed\n");
            goto save_end;
        }
        uart_printf("Save data CHANGED\n");
        reg_cartram_dirty = 0;
    }

    strcat(path, core_backup_name);
    if (f_open(&f, path, FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) {
        status("Cannot write save file");
        uart_printf("Cannot write save file");
        r = 2;
        goto save_end;
    }
    unsigned int bw;
    // for (int off = 0; off < size; off += bw) {
    // 	if (f_write(&f, bsram, 1024, &bw) != FR_OK) {
    uart_printf("Writing save file to: %s, len=%d\n", core_backup_name, size);
    if (f_write(&f, bsram, size, &bw) != FR_OK || bw != size) {
        status("Write failure");
        uart_printf("Write failure, bw=%d\n", bw);
        r = 2;
        goto bsram_save_close;
    }
    // }

bsram_save_close:
    f_close(&f);

save_end:
    uart_printf("backup_save: end\n");
    return r;
}

int backup_success_time;
void backup_process() {
    if (!core_running)
        return;
    int size = 0;
    if (CORE_ID == CORE_GBA) {
        // if (gba_backup_type == GBA_BACKUP_NONE || gba_backup_type == GBA_BACKUP_EEPROM)     // disable EEPROM persistence for now
        if (gba_backup_type == GBA_BACKUP_NONE)
            return;
        if (gba_backup_type == GBA_BACKUP_FLASH1M) 
            size = 128*1024;
        else if (gba_backup_type == GBA_BACKUP_EEPROM)
            size = 8*1024;
        else
            size = 64*1024;
    } else if (CORE_ID == CORE_SNES) {
        if (!option_backup_bsram || core_backup_size == 0)
            return;
        size = core_backup_size;
    } else
        return;
    int t = time_millis();
    if (t - core_backup_time >= 10000) {                    // need to save
        // uart_printf("CHECK 4F4=%x\n", *(volatile uint32_t *)0x4f4);
        uart_printf("Check backup: type=%d, size=%d\n", gba_backup_type, size);
        int r = backup_save(core_backup_name, size);
        // uart_printf("CHECK 4F4=%x\n", *(volatile uint32_t *)0x4f4);
        if (r == 0)
            backup_success_time = t;
        if (backup_success_time != 0) {
            status("");
            printf("Backup saved to sdcard %ds ago ", (t-backup_success_time)/1000);
            print_hex_digits(snes_bsram_crc16, 4);
        }
        core_backup_time = t;
    }
}

#define CRC16 0x8005

uint16_t gen_crc16(const volatile uint8_t *data, int size) {
    uint16_t out = 0;
    int bits_read = 0, bit_flag;

    /* Sanity check: */
    if(data == NULL)
        return 0;

    while(size > 0)
    {
        bit_flag = out >> 15;

        /* Get next bit: */
        out <<= 1;
        out |= (*data >> bits_read) & 1; // item a) work from the least significant bits

        /* Increment bit counter: */
        bits_read++;
        if(bits_read > 7)
        {
            bits_read = 0;
            data++;
            size--;
        }

        /* Cycle check: */
        if(bit_flag)
            out ^= CRC16;

    }

    // item b) "push out" the last 16 bits
    int i;
    for (i = 0; i < 16; ++i) {
        bit_flag = out >> 15;
        out <<= 1;
        if(bit_flag)
            out ^= CRC16;
    }

    // item c) reverse the bits
    uint16_t crc = 0;
    i = 0x8000;
    int j = 0x0001;
    for (; i != 0; i >>=1, j <<= 1) {
        if (i & out) crc |= j;
    }

    return crc;
}

int main() {
    CORE_ID = reg_core_id;
    overlay(1);

    // initialize UART
    if (CORE_ID == 3) {     // GBA core uses 16.78Mhz clock
        reg_uart_clkdiv = 138; // 16777216 / 115200;
    } else {
        reg_uart_clkdiv = 187; // 21505400 / 115200;
    }

    sd_init();
    delay(100);
    DEBUG("CORE_ID=%d\n", CORE_ID);
    
    int mounted = 0;
    while(!mounted) {
        for (int attempts = 0; attempts < 255; attempts++) {
            if (f_mount(&fs, "", 0) == FR_OK) {
                mounted = 1;
                break;
            }
        }
        if (!mounted)
            message("Insert SD card and press any key", 1);
    }

    int r = load_option();
    if (r == 2) {	// file corrupt
        clear();
        message("Option file corrupt and is not loaded",1);
    } else if (r == 1) {	// file not exist
        // clear();
        // message("Cannot open option file",1);
    }

    for (;;) {
        // main menu
        clear();
        cursor(2, 10);
        //     01234567890123456789012345678901
        if (CORE_ID == 1)
            print("=== Welcome to NESTang ===");
        else if (CORE_ID == 2)
            print("~~~ Welcome to SNESTang ~~~");
        else if (CORE_ID == 3)
            print("### Welcome to GBATang ###");
        else if (CORE_ID == 4)
            print("@@@ Welcome to MDTang @@@");
        else
            print("--- Welcome to New Core ---");

        cursor(2, 12);
        print("1) Load ROM from SD card\n");
        cursor(2, 13);
        print("2) Select core\n");
        cursor(2, 14);
        print("3) Options\n");
        // cursor(2, 15);
        // print("4) Verify core\n");
        cursor(2, 16);
        print("Version: ");
        print(__DATE__);

        delay(300);

        int choice = 0;
        for (;;) {
            int r = joy_choice(12, 3, &choice, OSD_KEY_CODE);
            if (r == 1) break;
        }

        if (choice == 0) {
            int rom;
            delay(300);
            menu_loadrom(&rom);
        } else if (choice == 1) {
            menu_select_core(0);
        } else if (choice == 2) {
            delay(300);
            menu_options();
            continue;
        } else if (choice == 3) {
            menu_select_core(1);
        }
    }
}

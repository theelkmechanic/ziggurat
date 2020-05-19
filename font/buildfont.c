#include <stdio.h>

void copyfile(const char *finname, FILE *fout)
{
	int siz=0;
	FILE *fin = fopen(finname, "rb");
	do {
		int ch = fgetc(fin);
		if (ch < 0) break;
		fputc(ch, fout);
		++siz;
	} while (!feof(fin));
	fclose(fin);
	printf("%d\n",siz);
}

int widennibble(int nibble)
{
	static const int widened[] = {
		0x00, 0x03, 0x0c, 0x0f,
		0x30, 0x33, 0x3c, 0x3f,
		0xc0, 0xc3, 0xcc, 0xcf,
		0xf0, 0xf3, 0xfc, 0xff
	};
	return widened[nibble & 0x0f];
}

void widenfile(const char *finname, FILE *fout)
{
	int siz=0;
	FILE *fin = fopen(finname, "rb");
	do {
		int ch = fgetc(fin);
		if (ch < 0) break;
		fputc(widennibble(ch >> 4), fout);
		fputc(widennibble(ch), fout);
		++siz;
	} while (!feof(fin));
	fclose(fin);
	printf("%d\n",siz);
}

void main()
{
	FILE *fout = fopen("../dats/ZIGGURAT.FNT", "wb");
	copyfile("zmch-baselo-charset.prg", fout);
	copyfile("zmch-basehi-charset.bin", fout);
	widenfile("zmch-overlay0-charset.bin", fout);
	widenfile("zmch-overlay1-charset.bin", fout);
	widenfile("zmch-overlay2-charset.bin", fout);
	widenfile("zmch-overlay3-charset.bin", fout);
	widenfile("zmch-overlay4-charset.bin", fout);
	widenfile("zmch-overlay5-charset.bin", fout);
	widenfile("zmch-overlay6-charset.bin", fout);
	widenfile("zmch-overlay7-charset.bin", fout);
	fclose(fout);
}

---
title: iOS逆向学习（二）砸壳原理之dumpdecrypted
date: 2019-06-20 23:00:00
tags: [iOS, 逆向]
---

## 1、基本原理
从AppStore中下载的包，是被苹果使用FairPlay技术加密的，没办法直接重签名给其他人用，也不能做IDA分析之类的逆向操作。所以为了得到没有加密的包，就需要进行砸壳操作。

看完Mach-O文件跟dyld加载介绍后，使劲拍拍脑袋能想到两种砸壳思路：

- 1. 直接破解FairPlay加密技术：很可惜暂时做不到，还没有公开的破解方案出来
- 2. 从APP的加载运行入手，越过解密阶段，直接从内存中读取被dyld解密后的内容

所以目前常见的砸壳工作，都是使用第二种思路来做的，这里我们以dumpdecrypted为例进行分析。

## 2、dumpdecrypted
dumpdecrypted分为[初代stefanesser做的版本](https://github.com/stefanesser/dumpdecrypted)，和后面[conradev改进的版本](https://github.com/conradev/dumpdecrypted)。但其原理基本不变，改进版主要是为了能够dump出动态加载库。咱们这次的分析以改进版的为例，先看使用步骤：

- 1、make生成.dylib文件
- 2、使用ssh把dylib文件放入目标app的沙盒路径下
- 3、执行砸壳并导出砸壳后的ipa文件

除了使用步骤以外，dumpdecrypted还要求手机中已经安装了cycript。所以我们不难看出，dumpdecrypted是通过dylid的方式，介入到dyld的加载过程中的。

然后再看源码，主要定义了三个函数：`dumptofile`、`image_added`、`dumpexecutable`，没有main函数。但可以看出这三个函数大致的调用关系，是`dumpexecutable` -> `image_added` -> `dumptofile`。继续分析，`dumpexecutable`是如何被调用的呢。答案在于其方法定义上：

```
__attribute__((constructor))
static void dumpexecutable() {
}
```
把换行去掉，就成了

```
__attribute__((constructor)) static void dumpexecutable() {
}
```
其中比较特殊的是`__attribute__((constructor))`这一段，可以大致理解成使用这段话，让我们新定义的`dumpexecutable`方法，在main函数之前被执行。而其得以做到的原因，就在于首先`constructor`函数，是在main函数之前执行的，而`__attribute__`修饰，又使得我们新定义的方法，可以和`constructor`一道，在main函数之前执行。这部分更详细的解释可以参照GUNC的文档

> [The constructor attribute causes the function to be called automatically before execution enters main ().](https://gcc.gnu.org/onlinedocs/gcc-6.2.0/gcc/Common-Function-Attributes.html)

所以重新梳理一下大致的调用关系：`constructor` -> `dumpexecutable` -> `image_added` -> `dumptofile`，需要注意这里说的调用关系仅仅是大致的。

弄清了整个的启动时机后，再看`dumpexecutable`函数内部，实际的操作只做了一件事：`_dyld_register_func_for_add_image(&image_added);`。因为咱们已经意识到整个砸壳过程是跟dyld有关的，所以可以从dyld源码中找到对`_dyld_register_func_for_add_image`的解释

```
/*
 * _dyld_register_func_for_add_image registers the specified function to be
 * called when a new image is added (a bundle or a dynamic shared library) to
 * the program.  When this function is first registered it is called for once
 * for each image that is currently part of the program.
 */
void
_dyld_register_func_for_add_image(
void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide))
```
大致的意思，就是说注册了一个监听方法，用于监听bundle或者动态加载库的加载事件，而且加载事件，对于每个bundle或者动态库仅会触发一次。到这里，我们就可以梳理出整个砸壳工具的逻辑顺序了：

- 1. 伴随`constructor`函数的调用，在main函数执行前，调用`dumpexecutable`函数
- 2. 在`dumpexecutable`函数中，注册bundle或动态库的加载事件监听，而且其响应方法是`image_added`函数
- 3. 当bundle或者动态库被加载时，触发事件监听，调用`image_added`方法，并向其传递header结构体指针，和另外一个不知道有什么用的参数slide
- 4. 然后在`image_added`方法内，调用`dumptofile`函数，进行真正的文件导出工作

所以到这里，我们转向`dumptofile`函数，看一下其内部实现。越过前面的变量定义，首先看这一段

```
/* extract basename */
tmp = strrchr(rpath, '/');
printf("\n\n");
if (tmp == NULL) {
	printf("[-] Unexpected error with filename.\n");
	_exit(1);
} else {
	printf("[+] Dumping %s\n", tmp+1);
}
```
这块的作用，是把路径进行裁剪，得到目标APP的文件名。然后下面这一段：

```
/* detect if this is a arm64 binary */
if (mh->magic == MH_MAGIC_64) {
	lc = (struct load_command *)((unsigned char *)mh + sizeof(struct mach_header_64));
	printf("[+] detected 64bit ARM binary in memory.\n");
} else { /* we might want to check for other errors here, too */
	lc = (struct load_command *)((unsigned char *)mh + sizeof(struct mach_header));
	printf("[+] detected 32bit ARM binary in memory.\n");
}
```
大致的作用，是通过对Mach-O文件中，header的magic字段进行判断，判断当前可执行文件是32还是64位的。然后，因为Mach-O文件的内容是连续的，所以可以通过header指针加上header区间大小的方式，拿到load commands的指针。

拿到了指针之后，再下一段代码

```
for (i=0; i<mh->ncmds; i++) {
	if (lc->cmd == LC_ENCRYPTION_INFO || lc->cmd == LC_ENCRYPTION_INFO_64) {
```
通过`mh->ncmds`得到load commands数量，对所有load command进行遍历。而在for循环内部，则对load command进行类型判断，只有当是`LC_ENCRYPTION_INFO`或者`LC_ENCRYPTION_INFO_64`类型时，才进入下一步。在Mach-O文档里没有找到`LC_ENCRYPTION_INFO`，但是可以google一下，大致的意思是加密相关的。所以我们可以把这个if语句，简单的理解成过滤加密相关的load command。然后继续深入if语句内部，首先是这么一段：

```
eic = (struct encryption_info_command *)lc;
/* If this load command is present, but data is not crypted then exit */
if (eic->cryptid == 0) {
	break;
}
```
为了理解这段，得先看`encryption_info_command`的定义：

```
/*
 * The encryption_info_command contains the file offset and size of an
 * of an encrypted segment.
 */
struct encryption_info_command {
   uint32_t	cmd;		/* LC_ENCRYPTION_INFO */
   uint32_t	cmdsize;	/* sizeof(struct encryption_info_command) */
   uint32_t	cryptoff;	/* file offset of encrypted range */
   uint32_t	cryptsize;	/* file size of encrypted range */
   uint32_t	cryptid;	/* which enryption system,
				   0 means not-encrypted yet */
};
```
然后结合这段代码的注释理解下，大致意思可能是说从`LC_ENCRYPTION_INFO`类型的load command，取出数据的加密状态，如果不是被加密的状态就中断执行。继续往下看这一段：

```
off_cryptid=(off_t)((void*)&eic->cryptid - (void*)mh);
printf("[+] offset to cryptid found: @%p(from %p) = %x\n", &eic->cryptid, mh, off_cryptid);
printf("[+] Found encrypted data at address %08x of length %u bytes - type %u.\n", eic->cryptoff, eic->cryptsize, eic->cryptid);
```
第一句的意思，是通过`(void*)eic->cryptid`减去`(void*)mh`的方式，得到cryptid偏移量。然后最后一句，输出的日志里表示从`eic->cryptoff`开始，`eic->cryptsize`大小的区域，都是已经被dyld解密并加载后的内容。

继续看源码，下面跟着的一大段，主要用处是读取Mach-O文件的header内容，所以就不贴源码了。但其中比较特殊的一段if语句：

```
/* Is this a FAT file - we assume the right endianess */
if (fh->magic == FAT_CIGAM) {
```
这段的作用，是区分FAT类型Mach-O文件，然后重定位到真正的header地址。再往下：

```
strlcpy(npath, tmp+1, sizeof(npath));
strlcat(npath, ".decrypted", sizeof(npath));
strlcpy(buffer, npath, sizeof(buffer));

printf("[+] Opening %s for writing.\n", npath);
outfd = open(npath, O_RDWR|O_CREAT|O_TRUNC, 0644);
if (outfd == -1) {
	if (strncmp("/private/var/mobile/Applications/", rpath, 33) == 0) {
		printf("[-] Failed opening. Most probably a sandbox issue. Trying something different.\n");
		
		/* create new name */
		strlcpy(npath, "/private/var/mobile/Applications/", sizeof(npath));
		tmp = strchr(rpath+33, '/');
		if (tmp == NULL) {
			printf("[-] Unexpected error with filename.\n");
			_exit(1);
		}
		tmp++;
		*tmp++ = 0;
		strlcat(npath, rpath+33, sizeof(npath));
		strlcat(npath, "tmp/", sizeof(npath));
		strlcat(npath, buffer, sizeof(npath));
		printf("[+] Opening %s for writing.\n", npath);
		outfd = open(npath, O_RDWR|O_CREAT|O_TRUNC, 0644);
	}
	if (outfd == -1) {
		perror("[-] Failed opening");
		printf("\n");
		_exit(1);
	}
}
```
这块是创建一个文件路径并open得到句柄，里面一大堆复杂的if判断，主要是用来处理文件操作失败的情况。而这个新创建的文件，就是以后我们会得到的砸壳输出结果文件。继续往下：

```
/* calculate address of beginning of crypted data */
n = fileoffs + eic->cryptoff;
	
restsize = lseek(fd, 0, SEEK_END) - n - eic->cryptsize;			
lseek(fd, 0, SEEK_SET);
	
printf("[+] Copying the not encrypted start of the file\n");
/* first copy all the data before the encrypted data */
while (n > 0) {
	toread = (n > sizeof(buffer)) ? sizeof(buffer) : n;
	r = read(fd, buffer, toread);
	if (r != toread) {
		printf("[-] Error reading file\n");
		_exit(1);
	}
	n -= r;
	
	r = write(outfd, buffer, toread);
	if (r != toread) {
		printf("[-] Error writing file\n");
		_exit(1);
	}
}
	
/* now write the previously encrypted data */
printf("[+] Dumping the decrypted data into the file\n");
r = write(outfd, (unsigned char *)mh + eic->cryptoff, eic->cryptsize);
if (r != eic->cryptsize) {
	printf("[-] Error writing file\n");
	_exit(1);
}
```
这块就是向输出文件写入数据了，主要分成三步：

- 第一步：计算并定位到解密数据的起始位置
- 第二步：把解密数据位置前的数据，写入到输出文件内，这部分的数据估计是包含了header的标识位信息
- 第三步：把解密数据写入到文件内。

然后再往下，直到整个`dumptofile`函数结束，剩下的代码段的作用，在于把剩下的数据一并写入输出文件里，并关闭文件句柄。

至此整个dumpdecrypted砸壳工具的代码已经分析完了，但是也留下了这几个问题：

- ***在判断加密状态那一段，当数据处于非加密的时候，为什么是break，而不是continue***
- ***在数据读取及写入阶段，加密数据段之前、之后的内容，具体是哪些数据***

这些问题估计可以从Mach-O文件格式里面找到答案，所以还得再回头研究Mach-O文件。

## 3、参考资料

- Mach-O文档：[https://web.archive.org/web/20090901205800/http://developer.apple.com/mac/library/documentation/DeveloperTools/Conceptual/MachORuntime/Reference/reference.html#//apple_ref/doc/uid/TP40000895-CH248-95908](https://web.archive.org/web/20090901205800/http://developer.apple.com/mac/library/documentation/DeveloperTools/Conceptual/MachORuntime/Reference/reference.html#//apple_ref/doc/uid/TP40000895-CH248-95908)
- dyld源码：[https://github.com/opensource-apple/dyld](https://github.com/opensource-apple/dyld)
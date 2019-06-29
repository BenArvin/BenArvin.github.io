---
title: iOS逆向学习（三）砸壳原理之frida-ios-dump
date: 2019-06-29 23:00:00
tags: [iOS, 逆向]
---

[frida-ios-dump](https://github.com/AloneMonkey/frida-ios-dump)是AloneMonkey写的iOS砸壳工具，虽然原理和dumpdecrypted相同，都是直接从内存中拷出被解密加载后的Mach-O文件，但实现细节上还是有差异。其中最重要的不同点，就在于对frida的使用上。

关于dumpdecrypted的原理分析，可以参照[上一篇文章](https://benarvintec.com/2019/06/20/iOS逆向学习（二）砸壳原理之dumpdecrypted/)

## 1、frida-ios-dump
先分析frida-ios-dump源码，主要是四个文件：dump.py、dump.js、process.sh、requirements.txt。其中主要起作用的，是dump.py和dump.js两个文件。requirements.txt是用来配置环境的，里面列出了依赖的各种库。process.sh暂时没用到，不清楚是做什么的先不管。

回到使用步骤上来，可以看出入口是在dump.py里面的，也就是下面这段：

```
if __name__ == '__main__':
	parser = argparse.ArgumentParser(description='frida-ios-dump (by AloneMonkey v2.0)')
	...
```
然后一步步的往下看，首先是解析命令行参数

```
parser = argparse.ArgumentParser(description='frida-ios-dump (by AloneMonkey v2.0)')
parser.add_argument('-l', '--list', dest='list_applications', action='store_true', help='List the installed apps')
parser.add_argument('-o', '--output', dest='output_ipa', help='Specify name of the decrypted IPA')
parser.add_argument('target', nargs='?', help='Bundle identifier or display name of the target app')
args = parser.parse_args()
```
然后是获取当前device句柄

```
device = get_usb_iphone()
```
点进`get_usb_iphone`函数里面，可以看到其核心是这一句

```
device_manager = frida.get_device_manager()
```
通过frida拿到deviceManager然后进行遍历。然后继续往下看，是对命令行传参的if判断。我们去掉list application之类的逻辑，直奔砸壳功能的话，就到了最后一个else里面的这一段

```
try:
	ssh = paramiko.SSHClient()
	ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
	ssh.connect(Host, port=Port, username=User, password=Password)
	create_dir(PAYLOAD_PATH)
	(session, display_name, bundle_identifier) = open_target_app(device, name_or_bundleid)
	if output_ipa is None:
	    output_ipa = display_name
	output_ipa = re.sub('\.ipa$', '', output_ipa)
	if session:
	    start_dump(session, output_ipa)
```
这一段的作用，主要是先构造SSH连接，然后获取目标APP的session，最后就是最主要的`start_dump`函数了。不过在看`start_dump`函数之前，先看一下构造session的操作，点进`open_target_app`函数，可以看到主要分成两块：第一部分遍历查找目标APP

```
for application in get_applications(device):
    if name_or_bundleid == application.identifier or name_or_bundleid == application.name:
        pid = application.pid
        display_name = application.name
        bundle_identifier = application.identifier
```
和第二部分，构造session

```
session = device.attach(pid)
```
需要注意的是，我们这里的操作都是依赖device句柄的，而device句柄又是通过frida获取的。

看完前面的部分代码之后，我们进入最关键的`start_dump`函数，内容很少，关键就两行

```
script = load_js_file(session, DUMP_JS)
script.post('dump')
```
所做的工作，就是加载dump.js脚本，然后发送dump指令。而这块之所以需要加载js脚本，是因为fria的实现导致的，我们暂时不管后面再聊。现在就当作是简单调用，进入dump.js文件继续分析。

dump.js脚本里面，入口在`handleMessage`函数这。我们把无关核心功能的代码摘除掉，就变成了下面的样子

```
function handleMessage(message) {
    modules = getAllAppModules();
    loadAllDynamicLibrary(app_path);
    modules = getAllAppModules();
    for (var i = 0; i  < modules.length; i++) {
        var result = dumpModule(modules[i].path);
    }
}
```
看函数名可以大致分析出执行逻辑：获取所有APP组件 -> 加载所有动态库 -> 获取所有APP组件 -> 遍历组件并导出。

这个逻辑过程大致上比较容易理解，因为APP可能会使用到动态库，所以得先加载所有的动态库，然后再挨个导出，这样才不会因为遗漏内容导致导出失败。

但是有点让人无法理解的是，为什么要执行两遍`getAllAppModules`函数呢？点进去看，无非也就是调用`Process.enumerateModulesSync()`函数而已。为了搞明白这事，我们就得去查frida的API接口文档，里面没找到`enumerateModulesSync`接口，但是有个类似的`enumerateModules`接口

> Process.enumerateModules(): enumerates modules loaded right now, returning an array of Module objects.

所以我们大致可以判定，两次`Process.enumerateModulesSync()`接口是没必要的，仅保留第二次调用就够了。

继续看代码，我们先看是怎么加载所有APP组件的，也就是`loadAllDynamicLibrary`函数。这是个递归函数，我们把那些日志、判断都去掉，保留核心代码来分析

```
function loadAllDynamicLibrary(app_path) {
    var defaultManager = ObjC.classes.NSFileManager.defaultManager();
    var filenames = defaultManager.contentsOfDirectoryAtPath_error_(app_path, errorPtr);
    for (var i = 0, l = filenames.count(); i < l; i++) {
        var file_name = filenames.objectAtIndex_(i);
        var file_path = app_path.stringByAppendingPathComponent_(file_name);
        if (file_name.hasSuffix_(".framework")) {
            var bundle = ObjC.classes.NSBundle.bundleWithPath_(file_path);
            bundle.load()
        } else if (file_name.hasSuffix_(".bundle") || 
                   file_name.hasSuffix_(".momd") ||
                   file_name.hasSuffix_(".strings") ||
                   file_name.hasSuffix_(".appex") ||
                   file_name.hasSuffix_(".app") ||
                   file_name.hasSuffix_(".lproj") ||
                   file_name.hasSuffix_(".storyboardc")) {
            continue;
        } else {
            var isDirPtr = Memory.alloc(Process.pointerSize);
            Memory.writePointer(isDirPtr,NULL);
            defaultManager.fileExistsAtPath_isDirectory_(file_path, isDirPtr);
            if (Memory.readPointer(isDirPtr) == 1) {
                loadAllDynamicLibrary(file_path);
            } else {
                if (file_name.hasSuffix_(".dylib")) {
                    var is_loaded = 0;
                    for (var j = 0; j < modules.length; j++) {
                        if (modules[j].path.indexOf(file_name) != -1) {
                            is_loaded = 1;
                            break;
                        }
                    }
                    if (!is_loaded) {
                        dlopen(file_path.UTF8String(), 9)
                    }
                }
            }
        }
    }
}
```
先是for循环跟之前的部分，这部分的作用是获取app_path路径下的所有文件、文件夹的路径，然后进入for循环开始遍历。进了for循环以后，就是针对路径类型的一个if判断。在判断里，把路径分成了四大类：

- framework：获取class并调用load进行加载
- dylib：判断是否已经被dyld加载过，如果没有就进行加载
- bundle、momd等类型文件：不处理，直接略过
- 文件夹：进入递归

而之所以要在这里把所有组件都加载到内存中，上一篇中我们介绍过，因为直接读取导出被加载到内存中的组件，就可以绕过苹果的FairPlay加密了。

最后，我们进入导出函数也就是`dumpModule`里面，分块进行分析，首先是这一段

```
var targetmod = null;
for (var i = 0; i < modules.length; i++) {
    if (modules[i].path.indexOf(name) != -1) {
        targetmod = modules[i];
        break;
    }
}
```
这一段的作用，是通过我们传入函数组件名，从组件列表里取出对应的组件。然后这一句

```
var modbase = modules[i].base;
```
是获取组件起始位置，后面在拿取magic之类的header信息的时候会用到。再然后这一段

```
var fmodule = open(newmodpath, O_CREAT | O_RDWR, 0);
var foldmodule = open(oldmodpath, O_RDONLY, 0);
```
创建了新旧文件句柄，用于后面的导入操作。继续往下看

```
var is64bit = false;
var size_of_mach_header = 0;
var magic = getU32(modbase);
var cur_cpu_type = getU32(modbase.add(4));
var cur_cpu_subtype = getU32(modbase.add(8));
if (magic == MH_MAGIC || magic == MH_CIGAM) {
    is64bit = false;
    size_of_mach_header = 28;
}else if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
    is64bit = true;
    size_of_mach_header = 32;
}
```
这一块是读取Mach-O文件的Header信息，不过这里面`is64bit`变量后面没用到。然后紧接着的是对Fat Mach-O文件的判断

```
magic = getU32(buffer);
if(magic == FAT_CIGAM || magic == FAT_MAGIC){
```
再继续这段

```
var ncmds = getU32(modbase.add(16));
var off = size_of_mach_header;
var offset_cryptid = -1;
var crypt_off = 0;
var crypt_size = 0;
var segments = [];
for (var i = 0; i < ncmds; i++) {
    var cmd = getU32(modbase.add(off));
    var cmdsize = getU32(modbase.add(off + 4));
    if (cmd == LC_ENCRYPTION_INFO || cmd == LC_ENCRYPTION_INFO_64) {
        offset_cryptid = off + 16;
        crypt_off = getU32(modbase.add(off + 8));
        crypt_size = getU32(modbase.add(off + 12));
    }
    off += cmdsize;
}
```
是为了计算马上要导出内容的偏移位置和大小，在其中我们又看到了上一篇中出现过的这个判断

```
if (cmd == LC_ENCRYPTION_INFO || cmd == LC_ENCRYPTION_INFO_64) {
```
最后，在拿到了所需要的一切信息之后，我们就可以正式开始导出操作了

```
if (offset_cryptid != -1) {
    var tpbuf = malloc(8);
    putU64(tpbuf, 0);
    lseek(fmodule, offset_cryptid, SEEK_SET);
    write(fmodule, tpbuf, 4);
    lseek(fmodule, crypt_off, SEEK_SET);
    write(fmodule, modbase.add(crypt_off), crypt_size);
}
```
至于剩下的代码，大多是一些关于文件句柄的操作。所以到此为止，我们已经把整个源代码都分析完了。可以看出来，相对于上一篇中分析的dumpdecrypted工具，其主要区别在于下面这几点上：

- Mach-O文件的加载方式：dumpdecrypted中需要我们自己触发APP的启动，而这里则是通过frida去主动加载的
- 处理的文件类型：因为不像dumpdecrypted那样，只是对Fat Mach-O文件进行了特殊处理，而是遍历了所有路径，所以不会漏过APP插件

## 2、frida
上面分析了frida-ios-dump工具源码，可以看到其能力是基于frida框架的，那frida到底是什么？直接引用官网上的介绍

> It’s Greasemonkey for native apps, or, put in more technical terms, it’s a dynamic code instrumentation toolkit. It lets you inject snippets of JavaScript or your own library into native apps on Windows, macOS, GNU/Linux, iOS, Android, and QNX. Frida also provides you with some simple tools built on top of the Frida API. These can be used as-is, tweaked to your needs, or serve as examples of how to use the API.

frida是一个用于原生APP的油猴脚本，或者更准确的说，是一个动态代码框架。而且更重要的，frida是各平台通用的。因为还没有深入研究frida框架，所以这里我们先简单介绍并分析下其能力。

刚才我们提到frida是平台通用的，适用于iOS、Android等等平台。而其之所以能做到平台通用，可以在下面这段里找到答案

> Frida’s core is written in C and injects Google’s V8 engine into the target processes, where your JS gets executed with full access to memory, hooking functions and even calling native functions inside the process. There’s a bi-directional communication channel that is used to talk between your app and the JS running inside the target process.

简要的说，就是frida是通过JS引擎，解析我们编写的JS脚本，然后转化成各平台下可运行的执行代码，有点类似各种iOS动态更新库的做法。这也就解释了为什么在frida-ios-dump里面，我们要通过dump.py执行dump.js文件。用图表来表示的话，大概就像下面这样子

`.js -> V8 engine/JSCore... -> C++/C/asm...`

弄明白大概原理以后，我们看下frida的能力。官网文档上说有三种模式，原文太长就不贴了，大致解释下这三种能力的作用范围：

- Injected：用在越狱设备上的模式，这种模式下可以加载APP、开启进程、链接设备，甚至劫持等一系列操作
- Embedded：用在非越狱设备上的模式，这种模式下能做的事就少了许多，而且还得把frida-gadget库集成到APP里面，不过好在只要集成了frida-gadget库，就可以进行远程操作了
- Preloaded：这个模式主要是用来在dyld加载之前做一些操作的

至于每种模式下的具体能力范围，就等后面深入研究了。

## 3、参考资料

- frida-ios-dump: [https://github.com/AloneMonkey/frida-ios-dump](https://github.com/AloneMonkey/frida-ios-dump)
- frida: [https://www.frida.re/docs/home/](https://www.frida.re/docs/home/)
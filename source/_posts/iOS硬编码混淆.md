---
title: iOS硬编码混淆
date: 2018-11-26 19:11:32
tags: [iOS, 混淆, 加固, Clang, Python, 算法]
---
在做iOS马甲包，或者加固的时候，我们需要进行代码混淆。目前比较成熟方便的解决方案，大多是采用[念茜大神博客](https://blog.csdn.net/yiyaaixuexi/article/details/29201699)里介绍的`#define`方式来做。

当然了，博客里给出的方案实现比较简陋，需要手动提取想要混淆的类及方法名。而且似乎因为版本更新等原因，这个比较旧的脚本现在也不能直接拿来用了，所以最好还是当作原理学习的样板吧。不过要是想找个立取可用的工具，可以用stevchen大神的开源工具[STCObfuscator](https://github.com/chenxiancai/STCObfuscator)。

相较于简陋的"原理样板"来说，`STCObfuscator`就很贴心了，先是用`runtime`+`linkmap`的方式，帮我们自动提取需要混淆的方法名和类名，然后又过滤掉对类名、方法名的硬编码引用。

但是除了类名、方法名的混淆以外，代码里的硬编码，比如最常见的写死了的字符串，也是有必要进行混淆的。

## 1. 分析实现
硬编码的类型有很多种，凡是在代码里写死了的字符串、数字等等，都能算作是。但对于马甲包或者加固工作来说，影响比较大的还是字符串类型数据。那整个的混淆过程，就可以分成下面这几步：

- 1) 字符串代码块定位
- 2) 字符串代码块内容加密
- 3) 替换原代码块

经过这三步操作以后，我们的代码里，原先的字符串代码块文本内容，就变成了已经加密后的密文。不过这并不影响我们的使用，因为等需要用到这个字符串的时候，我们会通过原生端的解密方法解密出来。

### 1.1 字符串代码块定位
首先，***人工检测是不可能的，这辈子都不可能的***。而且对于字符串代码块的自动检测runtime是用不上了，所以最浅显的方案就是直接文本检查。即通过对原代码文本的检查，找出代码中字符串代码块的位置。目前采用的方案，是通过正则表达式，去查找`@"`开头，`"`结尾的代码块。例如对于下面这段代码，就可以定位出有两个字符串代码块。

```
- (void)testMethod
{
    NSString *testString = [NSString stringWithFormat:@"testContent: %@", @"abc\ndef"];
    NSLog(testString);
}
```
对于这种定位方案，其实没啥好说的，无非就是正则表达式写仔细点，尽量多的去匹配各种神奇的代码写法就好。而唯一需要注意的点，就在于面对带有`%@`这种占位符的字符串，如果没有筛选出占位符以外的字符串并混淆的方案，就暂时不要对它进行处理。而现有常见的占位符种类，可以参照[苹果的技术文档](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Strings/Articles/formatSpecifiers.html)，大致有这么多种。

### 1.2 字符串代码块内容加密
因为加密了以后的内容，还是需要解密后使用的，所以就不能用MD5算法这种不可逆的方式来做了。再加上考虑到解密操作对性能的影响，所以目前选用的加密方案，是速度比较快的AES方案。具体的加密模块代码实现，可以在各个论坛找到，在这里就不做太多介绍了。

### 1.3 替换原代码块
经过上一步的操作，我们已经得到了加密后的密文。再结合第一步中找到的代码块位置，我们就可以把原代码中的字符串代码块内容，替换成无法直接阅读的密文。

不过虽然这时加密的目的是做到了，但编译运行肯定会出错的。所以我们还得整一个解密方法类，跟一个定义了所有密文的定义文件。那到此为止，我们的工作就已经全部完成了，代码中的字符串代码块，也变成了`[BAHCKey02b5dc445f4c6f7c3c0a5e50d406cc65 BAHC_Decrypt]`类似的句子。

## 2. 代码地址
目前的工具已经做好了第一版，github地址[点这里](https://github.com/BenArvin/BAHardCodeEncoder)。

具体的使用方法可以参照readme文件的介绍。

## 3. 优化
虽然第一版的工具已经做出来了，但还是存在问题的，主要是下面这两个：

- 字符串代码块识别不够精准
- 反混淆速度太慢

### 3.1 提高字符串代码块识别精准度
因为目前的识别方式，是使用正则表达式去匹配，所以难免会漏掉一些神奇的代码写法，甚至于也会因为部分字符串内容的原因，导致识别结果出错。

那么该怎样去提高识别精准度呢？答案就是Clang。作为苹果官方编译器LLVM中的一部分，Clang对于OC语法的识别必须是非常精准的。所以，管他三七二十一，实践万岁，我们先来找个Clang的python库尝试跑一把。

libclang是Clang自带的提供给python用的接口库，[地址在这里](http://llvm.org/svn/llvm-project/cfe/trunk/bindings/python/)。当然了，想要用的话，还是得把整个Clang目录都下载下来。

好了，现在已经下载下来啦，我们就跑起来吧！想多了，很抱歉，文档奇缺，就只有几个没啥文档说明的例子，所以想要跑起来，那还真是有点难度的。所以咱们还是老老实实一步一步来，先了解下Clang的基本知识吧。

首先是Clang官方网站的标题: [Clang: a C language family frontend for LLVM](http://clang.llvm.org)。那这句话里的"前端"(frontend)到底啥意思呢？下面是百度百科的编译器词条中，对于前端的介绍:

>前端主要负责解析（parse）输入的源代码，由语法分析器和语意分析器协同工作。语法分析器负责把源代码中的‘单词’（Token）找出来，语意分析器把这些分散的单词按预先定义好的语法组装成有意义的表达式，语句 ，函数等等。例如“a = b + c;”前端语法分析器看到的是“a， =， b ， +， c;”，语意分析器按定义的语法，先把他们组装成表达式“b + c”，再组装成“a = b + c”的语句。前端还负责语义（semantic checking）的检查，例如检测参与运算的变量是否是同一类型的，简单的错误处理。最终的结果常常是一个抽象的语法树（abstract syntax tree，或 AST），这样后端可以在此基础上进一步优化，处理。

所以简而言之，Clang的工作，就是把源代码处理成，可被LLVM识别的低级类汇编代码，也就是LLVM中间表达码(LLVM Intermediate Representation)。而Clang内部的工作步骤，则大致分成这么几步:

- 1) 预处理: 把`#include`的头文件中包含的内容，嵌入到目标代码文件之类的工作
- 2) 词法解析: 把预处理得到的代码文件，解析成抽象语法树(AST)
- 3) 静态分析: 对AST进行分析，找出代码中的一部分错误
- 4) 代码生成: 生成LLVM中间表达码
- 5) 优化: 把代码中的部分递归改成循环之类的工作

既然基本知识看完了，那么也就有了大致的实现方案，即通过对AST的读取，拿到字符串代码块的位置和内容。咱们先验证一下方案的可行性，下面是需要解析的原代码:

```
#import "TestClass.h"

#define TestDefine @"testDefineContent"

NSString *const testStatic = @"testStaticContent";

@implementation TestClass

- (void)test
{
    NSString *testVariable1 = @"testVariable1Content";
    NSLog(@"testLog");
    NSString *testVariable2 = @"testVariable2Content";
    NSString *testAssemble = [NSString stringWithFormat:@"%@%@", testVariable2, @"123"];
    NSLog(TestDefine);
}

@end
```

然后咱们使用Xcode自带的Clang工具，执行下面这行命令来导出AST:

`clang -Xclang -ast-dump TestClass.m`

运行结果长这样:

```
TestClass.m:9:9: fatal error: 'TestClass.h' file not found
#import "TestClass.h"
        ^~~~~~~~~~~~~
TranslationUnitDecl 0x7fde0a8012e8 <<invalid sloc>> <invalid sloc>
|-TypedefDecl 0x7fde0a801860 <<invalid sloc>> <invalid sloc> implicit __int128_t '__int128'
| `-BuiltinType 0x7fde0a801580 '__int128'
|-TypedefDecl 0x7fde0a8018d0 <<invalid sloc>> <invalid sloc> implicit __uint128_t 'unsigned __int128'
| `-BuiltinType 0x7fde0a8015a0 'unsigned __int128'
|-TypedefDecl 0x7fde0a801970 <<invalid sloc>> <invalid sloc> implicit SEL 'SEL *'
| `-PointerType 0x7fde0a801930 'SEL *'
|   `-BuiltinType 0x7fde0a8017c0 'SEL'
|-TypedefDecl 0x7fde0a801a58 <<invalid sloc>> <invalid sloc> implicit id 'id'
| `-ObjCObjectPointerType 0x7fde0a801a00 'id'
|   `-ObjCObjectType 0x7fde0a8019d0 'id'
|-TypedefDecl 0x7fde0a801b38 <<invalid sloc>> <invalid sloc> implicit Class 'Class'
| `-ObjCObjectPointerType 0x7fde0a801ae0 'Class'
|   `-ObjCObjectType 0x7fde0a801ab0 'Class'
|-ObjCInterfaceDecl 0x7fde0a801b90 <<invalid sloc>> <invalid sloc> implicit Protocol
|-TypedefDecl 0x7fde0a801ec8 <<invalid sloc>> <invalid sloc> implicit __NSConstantString 'struct __NSConstantString_tag'
| `-RecordType 0x7fde0a801cd0 'struct __NSConstantString_tag'
|   `-Record 0x7fde0a801c40 '__NSConstantString_tag'
|-TypedefDecl 0x7fde0a801f60 <<invalid sloc>> <invalid sloc> implicit __builtin_ms_va_list 'char *'
| `-PointerType 0x7fde0a801f20 'char *'
|   `-BuiltinType 0x7fde0a801380 'char'
|-TypedefDecl 0x7fde0a836a78 <<invalid sloc>> <invalid sloc> implicit __builtin_va_list 'struct __va_list_tag [1]'
| `-ConstantArrayType 0x7fde0a836a20 'struct __va_list_tag [1]' 1 
|   `-RecordType 0x7fde0a836890 'struct __va_list_tag'
|     `-Record 0x7fde0a836800 '__va_list_tag'
|-VarDecl 0x7fde0a836b30 <TestClass.m:13:1, col:17> col:17 invalid testStatic 'int *const'
|-ObjCInterfaceDecl 0x7fde0a836d08 <line:15:1, <invalid sloc>> col:17 implicit TestClass
| `-ObjCImplementation 0x7fde0a836e10 'TestClass'
|-ObjCImplementationDecl 0x7fde0a836e10 <col:1, line:26:1> line:15:17 TestClass
| |-ObjCInterface 0x7fde0a836d08 'TestClass'
| `-ObjCMethodDecl 0x7fde0a836f60 <line:17:1, line:24:1> line:17:1 - test 'void'
|   |-ImplicitParamDecl 0x7fde0a837018 <<invalid sloc>> <invalid sloc> implicit self 'TestClass *'
|   |-ImplicitParamDecl 0x7fde0a8370a0 <<invalid sloc>> <invalid sloc> implicit _cmd 'SEL':'SEL *'
|   `-CompoundStmt 0x7fde0a837630 <line:18:1, line:24:1>
|     |-CallExpr 0x7fde0a8374a0 <line:20:5, col:21> 'void'
|     | |-ImplicitCastExpr 0x7fde0a837488 <col:5> 'void (*)(id, ...)' <FunctionToPointerDecay>
|     | | `-DeclRefExpr 0x7fde0a837378 <col:5> 'void (id, ...)' Function 0x7fde0a837218 'NSLog' 'void (id, ...)'
|     | `-ImplicitCastExpr 0x7fde0a8374d0 <col:11, col:12> 'id':'id' <BitCast>
|     |   `-ObjCStringLiteral 0x7fde0a837408 <col:11, col:12> 'NSString *'
|     |     `-StringLiteral 0x7fde0a8373d8 <col:12> 'char [8]' lvalue "testLog"
|     `-CallExpr 0x7fde0a8375e8 <line:23:5, col:21> 'void'
|       |-ImplicitCastExpr 0x7fde0a8375d0 <col:5> 'void (*)(id, ...)' <FunctionToPointerDecay>
|       | `-DeclRefExpr 0x7fde0a837548 <col:5> 'void (id, ...)' Function 0x7fde0a837218 'NSLog' 'void (id, ...)'
|       `-ImplicitCastExpr 0x7fde0a837618 <line:11:20, col:21> 'id':'id' <BitCast>
|         `-ObjCStringLiteral 0x7fde0a8375b0 <col:20, col:21> 'NSString *'
|           `-StringLiteral 0x7fde0a837570 <col:21> 'char [18]' lvalue "testDefineContent"
`-FunctionDecl 0x7fde0a837218 <line:20:5> col:5 implicit used NSLog 'void (id, ...)' extern
  |-ParmVarDecl 0x7fde0a8372b8 <<invalid sloc>> <invalid sloc> 'id':'id'
  `-FormatAttr 0x7fde0a837320 <col:5> Implicit NSString 1 2
1 error generated.
```

仔细看一看执行结果，我们会发现有几行的首部写的是`StringLiteral`，而且该行的后面，的确跟着的是我们代码中写的字符串代码块内容，甚至于更棒的是，还标出了在原代码中的准确行列位置。

但是，再仔细对比一下源码，`testStatic`、`testVariable1`、`testVariable2`、`testAssemble`的内容都哪儿去了？为什么只剩下了`testLog`跟`testDefine`的内容。

这是因为，在预处理阶段，Clang就已经去除掉了无用的代码，而`testVariable1`等我们发现不见了的代码块，刚好就是因为没有引用到，所以就被摘除掉了。

但是这里还有有个疑点的，那就是对于`testStatic`，如果我们在`TestClass.h`文件中，声明了`extern`属性的话，`testStatic`就有可能在其他文件内被引用到了，不应该被从AST中去掉。所以按照这个猜想，我们把`TestClass.h`文件也纳入到刚才的代码行中，变成这样的写法:

`clang -Xclang -ast-dump TestClass.h TestClass.m`

这时候，我们发现命令行的运行结果中，的确是包含了`testStatic`代码块的信息。但整个的运行结果，也变成了28万多行之巨。这是因为在预处理时，Clang也把`#import <Foundation/Foundation.h>`时引入的`Foundation`代码，插入到了`TestClass`的代码中。

至此我们面临一个两难的选择: 要么只识别部分字符串代码块，要么就得在二十万多行的内容里去筛查。理所当然，这两种方案我们肯定都难以满意，甚至于难以实用化。那还有没有其他办法，能稍微让我们满意一些呢？试一下这行命令:

`clang -Xclang -dump-raw-tokens TestClass.m`

运行的结果是这样的:

```
comment '//'	 [StartOfLine]	Loc=<TestClass.m:1:1>
unknown '
'		Loc=<TestClass.m:1:3>
comment '//  TestClass.m'	 [StartOfLine]	Loc=<TestClass.m:2:1>
unknown '
'		Loc=<TestClass.m:2:16>
comment '//'	 [StartOfLine]	Loc=<TestClass.m:3:1>
unknown '
'		Loc=<TestClass.m:3:3>
comment '//'	 [StartOfLine]	Loc=<TestClass.m:4:1>
unknown '
'		Loc=<TestClass.m:4:3>
comment '//  Created by BenArvin on 2018/11/26.'	 [StartOfLine]	Loc=<TestClass.m:5:1>
unknown '
'		Loc=<TestClass.m:5:39>
comment '//  Copyright © 2018 BenArvin. All rights reserved.'	 [StartOfLine]	Loc=<TestClass.m:6:1>
unknown '
'		Loc=<TestClass.m:6:53>
comment '//'	 [StartOfLine]	Loc=<TestClass.m:7:1>
unknown '

'		Loc=<TestClass.m:7:3>
hash '#'	 [StartOfLine]	Loc=<TestClass.m:9:1>
raw_identifier 'import'		Loc=<TestClass.m:9:2>
unknown ' '		Loc=<TestClass.m:9:8>
string_literal '"TestClass.h"'		Loc=<TestClass.m:9:9>
unknown '

'		Loc=<TestClass.m:9:22>
hash '#'	 [StartOfLine]	Loc=<TestClass.m:11:1>
raw_identifier 'define'		Loc=<TestClass.m:11:2>
unknown ' '		Loc=<TestClass.m:11:8>
raw_identifier 'TestDefine'		Loc=<TestClass.m:11:9>
unknown ' '		Loc=<TestClass.m:11:19>
at '@'		Loc=<TestClass.m:11:20>
string_literal '"testDefineContent"'		Loc=<TestClass.m:11:21>
unknown '

'		Loc=<TestClass.m:11:40>
raw_identifier 'NSString'	 [StartOfLine]	Loc=<TestClass.m:13:1>
unknown ' '		Loc=<TestClass.m:13:9>
star '*'		Loc=<TestClass.m:13:10>
raw_identifier 'const'		Loc=<TestClass.m:13:11>
unknown ' '		Loc=<TestClass.m:13:16>
raw_identifier 'testStatic'		Loc=<TestClass.m:13:17>
unknown ' '		Loc=<TestClass.m:13:27>
equal '='		Loc=<TestClass.m:13:28>
unknown ' '		Loc=<TestClass.m:13:29>
at '@'		Loc=<TestClass.m:13:30>
string_literal '"testStaticContent"'		Loc=<TestClass.m:13:31>
semi ';'		Loc=<TestClass.m:13:50>
unknown '

'		Loc=<TestClass.m:13:51>
at '@'	 [StartOfLine]	Loc=<TestClass.m:15:1>
raw_identifier 'implementation'		Loc=<TestClass.m:15:2>
unknown ' '		Loc=<TestClass.m:15:16>
raw_identifier 'TestClass'		Loc=<TestClass.m:15:17>
unknown '

'		Loc=<TestClass.m:15:26>
minus '-'	 [StartOfLine]	Loc=<TestClass.m:17:1>
unknown ' '		Loc=<TestClass.m:17:2>
l_paren '('		Loc=<TestClass.m:17:3>
raw_identifier 'void'		Loc=<TestClass.m:17:4>
r_paren ')'		Loc=<TestClass.m:17:8>
raw_identifier 'test'		Loc=<TestClass.m:17:9>
unknown '
'		Loc=<TestClass.m:17:13>
l_brace '{'	 [StartOfLine]	Loc=<TestClass.m:18:1>
unknown '
    '		Loc=<TestClass.m:18:2>
raw_identifier 'NSString'	 [StartOfLine]	Loc=<TestClass.m:19:5>
unknown ' '		Loc=<TestClass.m:19:13>
star '*'		Loc=<TestClass.m:19:14>
raw_identifier 'testVariable1'		Loc=<TestClass.m:19:15>
unknown ' '		Loc=<TestClass.m:19:28>
equal '='		Loc=<TestClass.m:19:29>
unknown ' '		Loc=<TestClass.m:19:30>
at '@'		Loc=<TestClass.m:19:31>
string_literal '"testVariable1Content"'		Loc=<TestClass.m:19:32>
semi ';'		Loc=<TestClass.m:19:54>
unknown '
    '		Loc=<TestClass.m:19:55>
raw_identifier 'NSLog'	 [StartOfLine]	Loc=<TestClass.m:20:5>
l_paren '('		Loc=<TestClass.m:20:10>
at '@'		Loc=<TestClass.m:20:11>
string_literal '"testLog"'		Loc=<TestClass.m:20:12>
r_paren ')'		Loc=<TestClass.m:20:21>
semi ';'		Loc=<TestClass.m:20:22>
unknown '
    '		Loc=<TestClass.m:20:23>
raw_identifier 'NSString'	 [StartOfLine]	Loc=<TestClass.m:21:5>
unknown ' '		Loc=<TestClass.m:21:13>
star '*'		Loc=<TestClass.m:21:14>
raw_identifier 'testVariable2'		Loc=<TestClass.m:21:15>
unknown ' '		Loc=<TestClass.m:21:28>
equal '='		Loc=<TestClass.m:21:29>
unknown ' '		Loc=<TestClass.m:21:30>
at '@'		Loc=<TestClass.m:21:31>
string_literal '"testVariable2Content"'		Loc=<TestClass.m:21:32>
semi ';'		Loc=<TestClass.m:21:54>
unknown '
    '		Loc=<TestClass.m:21:55>
raw_identifier 'NSString'	 [StartOfLine]	Loc=<TestClass.m:22:5>
unknown ' '		Loc=<TestClass.m:22:13>
star '*'		Loc=<TestClass.m:22:14>
raw_identifier 'testAssemble'		Loc=<TestClass.m:22:15>
unknown ' '		Loc=<TestClass.m:22:27>
equal '='		Loc=<TestClass.m:22:28>
unknown ' '		Loc=<TestClass.m:22:29>
l_square '['		Loc=<TestClass.m:22:30>
raw_identifier 'NSString'		Loc=<TestClass.m:22:31>
unknown ' '		Loc=<TestClass.m:22:39>
raw_identifier 'stringWithFormat'		Loc=<TestClass.m:22:40>
colon ':'		Loc=<TestClass.m:22:56>
at '@'		Loc=<TestClass.m:22:57>
string_literal '"%@%@"'		Loc=<TestClass.m:22:58>
comma ','		Loc=<TestClass.m:22:64>
unknown ' '		Loc=<TestClass.m:22:65>
raw_identifier 'testVariable2'		Loc=<TestClass.m:22:66>
comma ','		Loc=<TestClass.m:22:79>
unknown ' '		Loc=<TestClass.m:22:80>
at '@'		Loc=<TestClass.m:22:81>
string_literal '"123"'		Loc=<TestClass.m:22:82>
r_square ']'		Loc=<TestClass.m:22:87>
semi ';'		Loc=<TestClass.m:22:88>
unknown '
    '		Loc=<TestClass.m:22:89>
raw_identifier 'NSLog'	 [StartOfLine]	Loc=<TestClass.m:23:5>
l_paren '('		Loc=<TestClass.m:23:10>
raw_identifier 'TestDefine'		Loc=<TestClass.m:23:11>
r_paren ')'		Loc=<TestClass.m:23:21>
semi ';'		Loc=<TestClass.m:23:22>
unknown '
'		Loc=<TestClass.m:23:23>
r_brace '}'	 [StartOfLine]	Loc=<TestClass.m:24:1>
unknown '

'		Loc=<TestClass.m:24:2>
at '@'	 [StartOfLine]	Loc=<TestClass.m:26:1>
raw_identifier 'end'		Loc=<TestClass.m:26:2>
unknown '
'		Loc=<TestClass.m:26:5>
ld: file not found: /var/folders/19/s4_rrq312qj3qflj0mmlpwnr0000gn/T/TestClass-216cbd.o
clang: error: linker command failed with exit code 1 (use -v to see invocation)
```

我们期待已久的结果终于得到了，只包含本文件内容，没有除去未引用的无用代码。要是libclang的python库中也包含相关的python接口，那就完美了。不过可惜的是，并没有找到相关的python接口，所以我们只能退而求其次，在python中执行bash命令，然后再以文本方式分析命令的运行结果，进而得到最终的字符串代码块位置和内容。

### 3.2 反混淆速度太慢
反混淆的意思，是指把已经被混淆了的代码恢复原样，这种操作的原理没啥好说的，就只是在代码里找到`[BAHCKey02b5dc445f4c6f7c3c0a5e50d406cc65 BAHC_Decrypt]`样式的代码块，替换成对应的解密后的字符串内容而已。

可是目前的第一版实现里，反混淆的速度是比较慢的，具体原因，还得从工作流程上找。现在代码的工作流程大致如下:

- 1) 把宏定义了所有加密后密文的`.h`文件，解析成字典
- 2) 逐个解析代码文件，在代码中查找是否包含字典中的值并替换

这种做法在代码量小的时候问题不大，但在大型工程里，解析后的字典key-value值会有成千上万个，导致挨个拿去在代码文本中查找的操作耗时太长。

当然，改进的方法肯定是有的，最简单的，我们可以先用正则表达式，去匹配出符合`[BAHCKey* BAHC_Decrypt]`样式的代码块，然后把这段代码块中的MD5值当作是key，去从字典中取出对应的字符串原文。

这么做肯定是快了许多，但问题在于为什么能变快？用key从字典中取值用到了哈希的原理，这我们都知道。可正则表达式为什么又能这么快呢？这个问题的答案，就得从算法层面去探究了。大致的解释，是因为通过对自动机的使用，使得算法复杂度大幅度降低了。这部分相关的内容，就留到后面再深入研究。

至此，代码优化的方向及解决方案都已经确定了，后面有空的话再做第二版的实现。

## 4. 附录
libclang python库的简单代码样例:

```
#!/usr/bin/python
# -*- coding: UTF-8 -*-

import sys, os
reload(sys)
sys.setdefaultencoding("utf-8")
import clang.cindex

def printDetail(cursor):
	print('\nspelling: ' + cursor.spelling + ' | kind: ' + str(cursor.kind) + ' | extent: ' + str(cursor.extent))

def iterAST(cursor):
	printDetail(cursor)
	for cursorItem in cursor.get_children():
		if cursorItem.get_children == None:
			printDetail(cursorItem)
		else:
			iterAST(cursorItem)

if __name__ == '__main__':
	#config libclang path, you can use 'clang --version' find it
	if clang.cindex.Config.loaded != True:
		clang.cindex.Config.set_library_path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib')
	index = clang.cindex.Index.create()
	# tu = index.parse(sys.argv[1], {"-Wunused"}, None, clang.cindex.TranslationUnit.PARSE_DETAILED_PROCESSING_RECORD)
	tu = index.parse(sys.argv[1], {"-Wunused"}, None, clang.cindex.TranslationUnit.PARSE_NONE)
	print('Translation unit:', tu.spelling)
	iterAST(tu.cursor)
```
这段代码的作用，是通过对libclang python库的使用，生成并解析AST。不过因为咱们解决方案的改变，这种方式最终还是没用上。但面对其他需求，还是有可用之处的。
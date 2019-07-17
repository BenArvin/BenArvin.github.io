---
title: 一种Swift下的不完美AOP方案
date: 2019-07-17 23:00:00
tags: [iOS, Swift, AOP]
---

因为Swift缺少动态性的问题，导致没办法像OC一样，通过runtime去实现AOP。虽然依旧可以通过在Swift代码中，添加`@objc`声明使之动态化的方式。但是这种做法，毕竟还是不Swift的。那么有没有办法，在不使用私有API的前提下实现AOP呢？

这里有个不完美的方案，即通过类的继承、引用和别名机制，来实现有条件的、受限的不完美AOP。

## 1、实现代码
原理很简单，所以我们就不介绍了，直接看代码。

先设定一个目标，即想要hook一个系统API，比如`UIView`的`layoutSubviews`方法。

### 1.1、第一步
先建立一个名叫`HookedUIKit`的framework工程，并在工程里面新增一个名叫`HookedUIView`的Swift类，类里面的代码这样写：

```
import UIKit
public class HookedUIView: UIView {
    override public func layoutSubviews() {
        super.layoutSubviews()
        //设置宽度为1.0的红色边框
        self.layer.borderColor = UIColor.red.cgColor
        self.layer.borderWidth = 1.0
    }
}
```
紧接着编译生成`HookedUIKit.framework`库文件

### 1.2、第二步
接下来创建一个名叫`SwiftAOPTest`的Swift工程，并引入上一步中我们制作好的`HookedUIKit.framework`库文件。

然后，在`SwiftAOPTest`工程里面，随便挑一个ViewController的代码文件，比如`MainViewController.swift`。并在文件顶部加上这两句：

```
import HookedUIKit
typealias UIView = HookedUIView
```
这一步结束之后，我们就做到了对`UIView`类里面`layoutSubviews`方法的hook，虽然有点怪怪的

### 1.3、验证
为了验证这个方案是不是有效，我们可以在`MainViewController.swift`文件里，随便新建并显示一个view，比如下面这样：

```
let tmpView = UIView.init(frame: CGRect.init(x: 50, y: 50, width: 50, height: 50))
tmpView.backgroundColor = UIColor.gray
self.view.addSubview(tmpView)
```
运行起来以后，我们就能看到这个view被加上了红色的边框

## 2、存在的问题
上面这种实现AOP的方式，其实是利用了对framework文件的引用，是单向性的特点。所以这种方案，也就脱离不了对这种单向引用特性的依赖。拓展来看的话，在下面这些场景里，刚才提到的方案都是无效的，或者需要增加很繁琐的特殊处理：

- hook framework库里面的类：可以尝试对需要引入的framework，再包一层framework
- hook本工程内其他同级类：比如工程里我们新增了个`DataManager`的业务类，而因为目前还没找到本工程内，对同级类的引用关系做单向限制的方法，所以这个方案也就是无效的
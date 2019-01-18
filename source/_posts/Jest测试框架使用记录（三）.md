---
title: Jest测试框架使用记录（三）
date: 2018-04-23 10:32:32
tags: [React Native, Jest]
---
紧接着上一篇，这次介绍的是Enzyme库。Enzyme是airbnb公司开源的测试工具库，可以和mocha、jest、karma等许多测试框架搭配使用，不过在这里，我们还是和jest框架搭配。具体的安装配置，可以参照[Enzyme官网](http://airbnb.io/enzyme/)。

# 1、官方测试工具库
因为Enzyme实际上是一个对官方测试工具库的封装，所以在介绍Enzyme之前，就先看下[官方测试工具库](https://reactjs.org/docs/test-utils.html)。

可以看到官方测试工具库，提供了一些诸如`isElement()`、`findAllInRenderedTree()`之类的方法，以帮助在测试例中获取节点、进行判断等操作。这样，我们就可以针对组件内部进行操作，最简单的例子就是模拟点击组件内的一个按钮。

不过虽然这样的确方便了不少，然而官方测试工具库提供的API却十分的简陋，而且大量的依赖组件的class、type、tag，使得使用起来也很不方便。所以，也就出现了一些对官方测试工具库的封装，其中比较出名的就是Enzyme。

最后，在介绍Enzyme之前，还得再说下[shalllow render](https://reactjs.org/docs/shallow-renderer.html)和[test render](https://reactjs.org/docs/test-renderer.html)。`test render`在第一篇中的快照测试部分有提到过，主要用来渲染出组件的虚拟结构，这样就可以在快照化后，保存成可读的文本文件。而`shallow render`则是`test render`中提供的另一种渲染方式，至于其作用也和`test render`类似。不过有所区别的是，渲染结果中所带的信息会更多一些，以方便配合官方测试工具库，对组件内的节点进行操作。同样的，下面我们要介绍的Enzyme，也需要用到`shallow render`。

# 2、Enzyme
打开Enzyme的介绍文档，可以看到其提供的API分为三组：`Shallow Rendering`、`Full DOM Renderning`和`Static Renderning`。

其中`Static Renderning`是用了第三方渲染库Cheerio，来进行更好的倾向于HTML内容的渲染，不过暂时我们还用不上。

而`Full DOM Renderning`则是通过依赖DOM API，进行全生命周期的渲染，可以简单的理解成会真的运行起来。不过虽然对于浏览器中的页面来说，因为浏览器提供了DOM API环境，可以很方便的做到这一点。但对于React Native代码来说，运行jest单元测试的时候是缺乏环境的，同时也因为React Native代码十分的依赖原生实现，所以暂时来说这种方式用处不大。不过如果能解决这些问题，那就可以更好的对React端，依赖生命周期等方法的逻辑进行测试，这部分的尝试，可以参照这两个git库：
[react-native-mock](https://github.com/RealOrangeOne/react-native-mock)、[react-native-mock-render](https://github.com/Root-App/react-native-mock-render)。

最后，我们现在需要用的就是最后一个`Shallow Rendering`，在这种方式下，我们是不需要依赖DOM API环境的，所以虽然牺牲了一些全生命周期渲染的优势，但还是能满足最基本的单元测试用途。这部分提供的API接口也很丰富，例如下面会常用到的这些：

- childAt()
- children()
- find(selector)
- get(index)
- props()
- parent()

有了这些API，我们就可以结合第一篇中的快照测试方法，进行更加细致的单元测试，比如下面这个例子：

```
let leftButtonCallback = jest.fn()
let rightButtonCallback = jest.fn()
let wrapper = shallow(<TestTitleBar titleContent={titleContent} leftButtonContent={leftButtonContent} rightButtonContent={rightButtonContent} onLeftButtonSelected={leftButtonCallback} onRightButtonSelected={rightButtonCallback}/>)

//快照测试
expect(wrapper).toMatchSnapshot()

//左侧按钮响应测试
expect(leftButtonCallback.mock.calls.length).toBe(0)
wrapper.find('TouchableOpacity').get(0).props.onPress()
expect(leftButtonCallback.mock.calls.length).toBe(1)

//右侧按钮响应测试
expect(rightButtonCallback.mock.calls.length).toBe(0)
wrapper.find('TouchableOpacity').get(1).props.onPress()
expect(rightButtonCallback.mock.calls.length).toBe(1)
```

当然，现在我们所能做的，就不仅仅局限于模拟点击事件这么简单了，其他的用处，可以结合实际需求，搭配适当的API方法来实现。

# 3、手动的自动测试
虽然我们现在有了Enzyme测试工具库，甚至于我们还可以参照`react-native-mock`的思路，引入`jsdom`库来提供DOM API环境，以实现全生命周期的测试。但到了最后，我们还是无奈的发现，就算我们做到了这些，还是无法解决React Native应用中，React端和原生端相互依赖带来的问题。

比如说对于路由组件`Navigator`来说，其对页面的调度、展现逻辑十分依赖原生端的实现，所以如果想要做到在React端实现全量测试，就得首先提供jsdom环境，然后再mock掉那些原生调用环节。这样的工作量是十分巨大的，而且一旦组件更新了，mock操作还可能需要相应的跟进迭代维护。所以总的来说，这种方式得不偿失。

那么对于这种情况的单元测试，目前采用的，则是一种手动的自动测试方式。即在真实环境下运行以后，手动执行一个自动测试代码块，然后通过log堆栈比对等方式，来检测是否测试通过。这种方式在技术的角度来看是十分笨的，但对于目前这种技术手段匮乏的情况下，也是一种无奈之举。所以，等后期如果发现有更好的方式再去替代吧。
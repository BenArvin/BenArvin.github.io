---
title: 更好地封装React Native组件（一）
date: 2018-02-27 17:32:42
tags: [React Native]
---
因为项目需要，前端时间封装了一个纯React Native端的，类似于iOS下UIActionSheet样式的，底部菜单弹窗组件[BAActionSheet](https://github.com/BenArvin/BAActionSheet)。

不同于以往的原生组件封装，纯React Native组件的封装，因为语言的原因受到了更多的限制。比如想要使用组件，就得先写进render()方法里。不能再像原生那样，需要显示的时候，才通过代码new出来然后addSubview进去。

也正是有了这些限制，对于React Native组件的封装，下面几个关键点就显得特别重要起来：

- 组件的接口必须清晰
- 组件的职责必须明确

# 1. 接口的清晰
下面一段是常见的原生Class定义：

```
//TestObject.h
@interface TestObject: NSObject

@property (nonatomic) NSString *title;
@property (nonatomic) BOOL enable;

- (void)testAction:(NSString *)param1 param2:(BOOL)param2;

@end
```
这样的代码，看起来十分清晰明确。我们可以一目了然的，迅速得到这个Class的属性、方法，以及属性的类型、方法的参数类型等等。

但在React Native项目内，我们常见的组件代码却可能是下面这样的：

```
class TestComponent extends React.Component {
    render() {
        return(
            <View>
                <Text>{this.props.title}</Text>
                <Text>{this.props.content}</Text>
            </View>
        )
    }

    testMethod1(param1, param2) {
    }

    testMethod2(param1, param2) {
    }
}
```
相较于原生代码例子的一目了然，这个React Native的例子里，既没有在一个统一固定的地方，列出所有的`props`，也没有对`props`的类型进行约束，就更不要谈什么默认值，甚至`testMethod1 `和`testMethod2`到底哪个是公有方法了。

当然，毕竟这个例子代码量很小，其实这样写问题也是不大的。但如果是个复杂的组件，就有可能有着几十个`props`和几十个方法。所以，对于会面向其他开发人员的开放组件来说，这种致命的问题必须去尽力的避免。

而解决办法也肯定是有的，只不过没有那么完美罢了：

```
import PropTypes from "prop-types";

class TestComponent extends React.Component {

    static propTypes = {
        title: PropTypes.string,
        content: PropTypes.shape({
            firstContent: PropTypes.string,
            secondContent: PropTypes.string,
        }),
        callback: PropTypes.func,
    }

    static defaultProps = {
        title: 'default title'
    }

    /*
    * test public method
    *
    * param1: PropTypes.string
    * param2: PropTypes.string
    * */
    testMethod1(param1, param2) {
    }

    _testMethod2(param1, param2) {
    }
}
```

- 第一，在`static propTypes = {}`中，我们可以列出所有将会用到的`props`
- 第二，在`static defaultProps = {}`中，我们又可以对默认值进行设置
- 第三，通过引入`prop-types`，我们可以对`props`的类型进行约束
- 最后，不太完美的是，我们没法儿约束方法的公有/私有性，也很难对其参数进行类似于`props`那样详尽的约束。所以，只好参照React Native源码，通过是否带下划线，来区分是不是私有方法。并通过注释，来明确方法参数的特性。

# 2. 职责的明确
以弹窗组件为例，我们可以认为其应有的职责，有这么三点：

- 在需要的时机，显示/隐藏弹窗
- 响应弹窗的点击事件
- 可一定程度的，更新/自定义UI样式

那么按照这三点职责，咱们就可以设计出第一套代码方案，剔除掉细节实现，大致结构如下所示：

```
export class ActionSheetDemo extends React.Component {
    static propTypes = {
        hide: PropTypes.bool,//控制弹窗是否显示
        title: PropTypes.string,//弹窗标题
        items: PropTypes.arrayOf(PropTypes.string),//弹窗选项
        onSelected: PropTypes.func//弹窗选项点击回调
    }

    static defaultProps = {
        hide: true//弹窗默认不显示
    }

    render() {
    }
}
```
对于这样的实现，我们只需要在想显示弹窗的地方，放上这么一段：

```
<ActionSheetDemo hide={this.isActionSheetHide} title={this.actionSheetTitle} items={this.actionSheetItems} onSelected={this.onActionSheetSelected} />
```
然后等显示/隐藏，或者修改弹窗UI样式的时候，先修改`this.isActionSheetHide`的值，再触发自身的`render`事件，进一步触发弹窗组件的`render`就可以了。

但这种方式是有问题的，即弹窗的职责已经超出了我们刚才限定的三条。

因为既然为了显示/隐藏或者修改弹窗UI，就得触发使用位置组件自身的`render`事件。那弹窗的职责，就超越了本身，侵入了使用弹窗位置组件的职责范围。所以为了解决这个问题，我们就得让弹窗和使用位置组件的`render`事件隔离开来。

```
export class ActionSheetDemo extends React.Component {
    static propTypes = {
        onSelected: PropTypes.func
    }

    render() {
    }

    //显示弹窗
    show() {
    }

    //隐藏弹窗
    hide() {
    }

    //修改弹窗UI样式
    configContent(title, items) {
    }
}
```
现在的代码里，我们对于弹窗的显示/隐藏，以及UI修改等操作，都不必再经由使用位置组件的`render`事件去触发了。只需要调用弹窗的`show()`、`hide()`、`configContent()`方法，就可以做到弹窗本身的独立`render`。

但这样是不是就已经没问题了呢？并不是。

虽然我们已经做到了把弹窗的职责，明确限制在其自身之内。但我们却没有解决弹窗使用位置的组件，侵入了弹窗本身职责范围的问题。举个例子：

```
export class PageDemo extends React.Component {
    render() {
        return(
            <View>
                <ActionSheetDemo />
            </View>
        )
    }
    
    _onEvent1() {
        this.setState()
    }

    _onEvent2() {
        this.setState()
    }
}
```
在`PageDemo`里，每一次像`_onEvent1()`、`_onEvent2()`之类，完全和弹窗没有关联的事件，都会触发`PageDemo`的`render`，从而进一步触发弹窗的`render`。所以，这种情况就属于外部组件侵入了弹窗的职责范围。为了解决这个问题，咱们的方案很简单，把：

```
export class ActionSheetDemo extends React.Component
```
替换成：

```
export class ActionSheetDemo extends React.PureComponent
```
或者，也可以在`ActionSheetDemo`内，通过重写`ShouldComponentUpdate()`方法，来隔离外部组件`render`事件对自身的影响。

# 3. 意外的收获
在第二节中，我们通过各种方式，对弹窗本身，和使用弹窗位置组件的职责，进行了明确严格的划分。而这种职责的明确，对于本文中的弹窗组件来说，最明显的作用，即在于性能上的提升。

如果我们没有明确组件的职责，那不可避免的，弹窗组件内外`render`操作将会连为一体。会导致每一次显示/隐藏，自定义弹窗UI样式的操作，乃至于外部的每一次无关弹窗的`render`，都会在对目的范围进行刷新操作之外，夹杂上大量无用的其他区域刷新操作。毫无疑问，这会带来严重的性能问题。

而现在，经过了一系列的设计改进，我们再也不用担心这种问题。因为我们可以做到，想刷新哪儿就只刷新哪儿，其余地方保持安静。当然了，第二节中我们的最终设计也并不是完美的，还存在一些没有考虑到首次`render`之类的问题，对于这些细节，就下一次再做讨论了。
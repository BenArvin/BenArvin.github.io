---
title: Jest测试框架使用记录（二）
date: 2018-03-05 11:58:17
tags: [React Native, Jest]
---
# 1、覆盖率
运行`jest --coverage`命令，就可以得到当前的覆盖率统计数据输出，大致像下面这样：

```
------------------------------|----------|----------|----------|----------|----------------|
File                          |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
------------------------------|----------|----------|----------|----------|----------------|
All files                     |     87.5 |      100 |    70.97 |     87.5 |                |
 SimpleJestDemo               |      100 |      100 |      100 |      100 |                |
  App.js                      |      100 |      100 |      100 |      100 |                |
 SimpleJestDemo/src           |    98.08 |      100 |    95.24 |    98.08 |                |
  NestedNativeComponent.js    |       75 |      100 |    66.67 |       75 |             23 |
  PureLogicMethods.js         |      100 |      100 |      100 |      100 |                |
  SimpleNativeView.js         |      100 |      100 |      100 |      100 |                |
  SnapshotComponent.js        |      100 |      100 |      100 |      100 |                |
------------------------------|----------|----------|----------|----------|----------------|
```
结果里给出了各个维度下的覆盖率，而且还贴心的给出了未被覆盖代码的具体位置，方便我们去检查修改。而至于各个维度的区别，简答的来说，要求不高就看`function(Funcs)`指标，也就是所有方法是否都被覆盖到。要求高就看`statements(Stmts)`指标，也就是所有执行单元是否都被覆盖到。具体各个指标的详细区别和释意，可以参照[这篇帖子](http://www.ncover.com/blog/understanding-branch-coverage/)。

# 2、mock
mock的意思，就是用新的实现，去替换掉源代码的实现。具体的使用方法，主要分成`mock functions`、`timer mock`，和`manual mock`三种。

## 2.1、mock functions
`mock functions`很简单，就是用新的jest.fn()类型function替换掉旧的，比如下面这个方法：

```
let nestedAddAction = function (value1, value2, callback) {
    callback(addAction(value1, value2))
}
```
平常使用的时候，我们会这样写：

```
PureLogicMehods.nestedAddAction(1, 2, () => {})
```
但有时候，为了知道回调方法到底有没有被调用，被调用了几次，或者回传的结果到底正不正确，我们就可以用一个jest.fn()去替换原有的回调方法：

```
let mockedCallback = jest.fn()//定义一个jest.fn()类型回调方法

PureLogicMehods.nestedAddAction(1, 2, mockedCallback)
expect(mockedCallback.mock.calls.length).toBe(1)//判断回调方法是不是被调用过

PureLogicMehods.nestedAddAction(2, 3, mockedCallback)
expect(mockedCallback.mock.calls.length).toBe(2)//判断回调方法是不是被调用了两次

expect(mockedCallback.mock.calls[0][0]).toBe(3)//判断第一次回调的返回值是不是3
expect(mockedCallback.mock.calls[1][0]).toBe(5)//判断第二次回调的返回值是不是5
```

其中`expect(mockedCallback.mock.calls[0][0]).toBe(3)`这一句里，句尾的第一个`[0]`，是指第一次运行的结果，第二个`[0]`是指这次回调所有返回值中的第一个。

## 2.2、timer mocks
`timer mocks`是用来替换`setTimeOut()`之类的定时器的，这样就可以不用真的等待定时器结束。例如下面这个方法就包含了定时逻辑：

```
let timeoutAction = function (param, callback) {
    setTimeout(() => {
        callback(param)
    }, 5000)
}
```
对于这个方法的测试例，我们就可以这样写：

```
jest.useFakeTimers()//声明要使用timer mocks
let mockedCallback = jest.fn()
PureLogicMehods.timeoutAction('test param', mockedCallback)
jest.runAllTimers()//执行假的定时器逻辑
expect(setTimeout).toHaveBeenCalledTimes(1)//判断定时器逻辑是不是执行过一次
expect(mockedCallback).toHaveBeenCalledTimes(1)
```

## 2.3、manual mock
相较于比较清晰的`mock functions`和`timer mock`来说，`manual mock`的各种使用方法和说明有些混乱，所以在这里就只介绍一些简单的，确实可行的使用方案。

### 2.3.1、简单方式
这种方式最简单，不需要新增`__mocks__`文件夹，只需要在测试例代码那儿，按需求mock就行。下面是个简单的例子：

```
//MockTestDependency.js
export default class MockTestDependency {
    testAction1() {
        return 'testAction1'
    }
    testAction2() {
        return 'testAction2'
    }
}
```

```
jest.mock('./MockTestDependency')

import MockTestDependency from "./MockTestDependency"

beforeAll(() => {
    MockTestDependency.mockImplementation(() => {
        return {
            testAction1: () => {return 'mocked1'},
            testAction2: () => {return 'mocked2'},
        }
    })
})

describe('mock test', () => {
    it('first case', () => {
        let mockTestDependency = new MockTestDependency()
        expect(mockTestDependency.testAction1()).toBe('mocked1')
        expect(mockTestDependency.testAction2()).toBe('mocked2')
    })
})
```
需要注意的是，`jest.mock()`的意思，是声明需要使用某个组件被替换后的实现。但同时，也会把组件内的所有实现都替换成`jest.fn()`。所以这种mock方式属于全面替换，做不到只替换`testAction1()`的同时，不影响`testAction2()`的原本实现。

另外，除了`mockImplementation`方法，还有`mockImplementationOnce`、`mockReturnValue`等，这些方法的使用相对而言基本大同小异，具体的使用方法可以参照[官网说明](https://facebook.github.io/jest/docs/en/mock-function-api.html#mockfnmockreturnvaluevalue)。

### 2.3.2、\_\_mocks\_\_方式
这种方式和上一种类似，都是全面替换。但使用起来稍微有些麻烦，需要在和被替换的目标js文件同层级的路径下，新建一个`__mocks__`文件夹，然后再在里面放一个和目标js同名的文件，这个文件就用来放替换后的实现。下面是个简单的例子：

```
文件结构：
├── __mocks__
│   └── MockTestDependency.js
├── MockTestDependency.js
└── MockTest.test.js
```

```
//MockTestDependency.js
export default class MockTestDependency {
    testAction1() {
        return 'testAction1'
    }
    testAction2() {
        return 'testAction2'
    }
}
```

```
//__mocks__/MockTestDependency.js
export default class MockTestDependency {
    testAction1() {
        return 'mocked1'
    }
    testAction2() {
        return 'mocked2'
    }
}
```

```
//MockTest.test.js
jest.mock('./MockTestDependency')

import MockTestDependency from "./MockTestDependency"

describe('mock test', () => {
    it('first case', () => {
        let mockTestDependency = new MockTestDependency()
        expect(mockTestDependency.testAction1()).toBe('mocked1')
        expect(mockTestDependency.testAction2()).toBe('mocked2')
    })
})
```
可以看到，使用这种方式时，就不需要在测试例代码里写`mockImplementation`了，所以相对而言比较简洁。

不过使用这种方法时，有下面几点尤其需要注意：

- 在测试用例文件`MockTest.test.js`里，一定要先写`jest.mock()`，再写`import`。因为只有在使用`jest.mock()`声明需要使用mock了的文件后，`import`时才会引入`__mocks__`路径下的替换文件。否则，引入的就依然还是原文件。
- 当mock的不是自建js文件，而是nodeModule内的文件时，不需要在nodeModule内每个需要mock的地方都新建`__mocks__`路径，只需要在和nodeModule同级的位置新建一个统一的`__mocks__`路径，然后把所有的替换文件都放里面就行了。

### 2.3.3、局部替换
上面的两种方法都属于全面替换，虽然可以做到对原文件中实现的替换，但实际项目中可能更多需要的，则是单独替换某个方法，而不影响其他方法。所以，为了达到这种效果，就可以使用`spyOn()`。下面是个简单的例子：

```
export class TestComponent extends React.Component {
    render() {
        return(
            <View>
                <Text>{this._getContent()}</Text>
            </View>
        )
    }
    _getContent() {
        return 'have not mocked'
    }
}
```

```
import React from 'react'
import testRenderer from "react-test-renderer";
import {TestComponent} from './MockTestDependency';

describe('mock test 1', () => {
    it('mock test 3', () => {
        let treeObejct = testRenderer.create(<TestComponent />)
        jest.spyOn(treeObejct.getInstance(), '_getContent').mockImplementation(() => {return 'mocked'})
        treeObejct.getInstance().forceUpdate()
        expect(treeObejct.toJSON()).toMatchSnapshot()
    })
})
```
这样，我们就可以做到只替换`_getContent()`方法，而不影响原有的`render()`方法内逻辑。但同样的，这种方式也有需要注意的点，即想要这种方式生效，就不能再用`jest.mock()`了。因为一旦使用了`jest.mock()`，就会把原文件中的所有实现都替换为`jest.fn()`，也就立刻的影响了所有逻辑。

此外，还有一个关于`snapshot`的注意点。上面的测试用例代码中，`jest.spyOn()`后，我们又执行了一次`forceUpdate`，那是因为`testRenderer.create()`时，`render()`方法就已经被调用了，如果不`forceUpdate`一次，我们替换后的结果就无法展现出来。

# 3、最后的最后
对于jest的学习，本意是希望通过对jest测试框架的使用，来固化一些单元测试。最终达到加速代码迭代的作用，同时也保障代码质量的稳定。而jest框架也的确为这种设想，提供了实现的可能。但随着把jest框架往项目里的代入，会发现还是有着许多限制和不便的。例如对于和原生交互较多的模块，就会因为jest仅仅作用于React层，而无法使用。当然了，虽然有这些限制和不便，jest还是值得使用的，毕竟在经历了漫长的版本迭代类型的代码开发工作之后，愈发的意识到了测试覆盖的重要性。所以，后面的话，可能会尝试jest框架和自建测试例并行的方式。到时成功的话就再拿出来分享，不成功的话，当然肯定就谁也不告诉了。
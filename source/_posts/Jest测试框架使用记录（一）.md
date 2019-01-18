---
title: Jest测试框架使用记录（一）
date: 2018-02-23 15:33:19
tags: [React Native, Jest]
---
# 1、基本配置
使用react-native init方式新建的React Native工程，现在都是已经默认安装好了Jest框架的。不过如果没有的话，也可以自己手动安装，具体方法可以参照[Jest官网教程](https://facebook.github.io/jest/docs/en/getting-started.html)。

# 2、简单使用
首先，新建一个JS文件``PureLogicMethods.js``，写入需要进行测试的逻辑代码段，例如一个加法函数：

```
let addAction = function (value1, value2) {
	return value1 + value2
}
exports.addAction = addAction
```

然后，再新建一个和需要测试的逻辑代码JS文件同名，但后缀中包含``.test``的Jest测试脚本，即相对应的就是``PureLogicMethods.test.js``，并在里面写上对加法函数进行单元测试的代码：

```
describe('enzyme test ', () => {
    it('add action test', () => {
        expect(PureLogicMehods.addAction(1, 2)).toBe(3)
    })
})
```
现在，就可以在终端执行``jest``命令，进行对加法函数的单元测试了。同样的，测试结果也会在终端上体现出来。

**需要注意的是：**测试脚本文件，其实不必一定和被测试JS文件同名，只需要后缀名是``.test.js``，Jest框架就会自动识别出来。不过，为了方便代码查阅，最好还是按照建议用同名的方式命名。

# 3、基本语法
Jest测试脚本的语法和Mocha大致类似，以第二节中的加法函数单元测试脚本为例：

- 第一行，``describe('xxx', () => {})``，意思是新建一个名叫xxx的测试套件（Test Suite）。此外，一个测试脚本文件内是可以定义多个测试套件的，运行时会依次的顺序执行。
- 第二行，``it('yyy', () => {})``，意思是新建一个包含在xxx测试套件内的，名叫yyy的测试用例（Test Case）。当然了，一个测试套件内也是可以包含多个测试用例的，运行时同样的也是依次的顺序执行。
- 第三行，``expect(valueA).toBe(valueB)``，意思是定义了一个断言，用来判断valueA是否和预期一样等于valueB。如果符合预期，那么就不抛出异常算是测试通过。反过来，如果不符合预期，就抛出异常算是测试不通过。在这个例子里，valueA就是当加法函数的传参是1和2时的返回值，valueB就是我们认为加法函数应该返回的正确值3。

除了例子里的简单使用，断言的其他高级使用在官网已经给出[文档介绍](https://facebook.github.io/jest/docs/en/expect.html)。

# 4、Snapshot（快照）
第二节的例子里，仅仅是对简单的纯逻辑代码进行测试，但如果要进行UI测试，就需要使用[Snapshot](https://facebook.github.io/jest/docs/en/snapshot-testing.html)。大致的过程，就是每次执行测试用例的时候，都序列化一个和我们UI组件的React tree相对应的纯文本的快照文件，然后再和上一次保存的快照文件进行比对，以发现哪些地方有了变化。

因此，这种快照的方式，总的来说还只是静态的比对，我也暂时还没找到使用快照对动画进行测试的方法。不过无论如何，至少好过没有，而且根据其他技术帖的说法，这种保存纯文本快照文件的方式，相较于另外一种真的是保存截图，然后一个像素一个像素进行对比的方式来说，性能上也肯定会好上许多。

## 4.1、静态UI组件的快照测试
首先，这里的静态组件，是指那种最简单的，直接代码写死不会运行时改变的UI组件。然后，快照测试脚本的编写，和第二节中简单逻辑代码测试脚本的编写大致类似。

- 第一步，新建一个包含了需要测试的UI组件的JS文件``StaticComponent.js``，其render方法如下：

```
render() {
    return (
        <View>
            <Text>static component for snapshot test</Text>
        </View>
    )
}
```
- 第二步，新建一个同名但是包含``.test``后缀的测试脚本文件``StaticComponent.test.js``，并写上对应的快照测试代码：

```
import testRenderer from 'react-test-renderer';

describe('UI component snapshot test', () => {
    it('static component', () => {
        expect(testRenderer.create(<StaticComponent />).toJSON()).toMatchSnapshot()
    })
})
```

- 第三步，执行``jest``命令，就可以在测试脚本所在的路径下，发现一个名为``__snapshots__``的文件夹，这里就保存着每次测试时生成的纯文本快照文件，例如和本例相对应的就是``StaticComponent.test.js.snap``

- 第四步，稍微修改一下``StaticComponent.js``文件里面的自定义组件，例如加上一个空的``<View />``

- 第五步，再次执行“jest”命令，就会发现此时终端输出的结果中，会提示我们UI组件有了改变，而且改变的位置也会清楚的告诉我们。这时，我们就可以根据提示，去 **肉眼** 查错了。当然，如果我们认为这些改变，其实是必要的修改而不是错误的话，我们也可以执行``jest --updateSnapshot``命令，去覆盖保存本次的快照结果。

**需要注意的是：**

- 自动生成的快照文件，是和测试脚本放在一个路径下的，而测试脚本又不必一定和被测试的JS文件放在同一个路径下。所以，项目内的所有快照测试脚本，可以统一放在一个路径下，以避免生成的快照文件散落各处。

- 按照建议，自动生成的快照文件，是需要上传git保存下来的，以方便团队协作时的使用。不过，如果生成的快照仅仅用于本地测试用，那也可以不必上传，但本地一定要做好保存，方便和下次生成的快照进行比对。

## 4.2、动态UI组件的快照测试
除去上一节中的静态UI组件，实际项目代码中更多的则是可以根据props、state改变的动态UI组件，例如下面这种：

```
export class DynamicComponent extends React.Component {
    static propTypes = {
        title: PropTypes.string,
        firstDomContext: PropTypes.string,
        secondDomContext: PropTypes.string,
    }

    constructor(props) {
        super(props)
        this.state = {
            enableFirstDom: false,
            enableSecondDom: false
        }
    }

    _buildFirstDom() {
        if (this.state.enableFirstDom) {
            return (<Text>{this.props.firstDomContext}</Text>)
        }
    }

    _buildSecondDom() {
        if (this.state.enableSecondDom) {
            return (<Text>{this.props.secondDomContext}</Text>)
        }
    }

    render() {
        return (
            <View>
                <Text>{this.props.title}</Text>
                {this._buildFirstDom()}
                {this._buildSecondDom()}
            </View>
        )
    }

    //显示第一条内容
    showFirstDom() {
        this.setState((prevState, props) => {return {enableFirstDom: true}})
    }

    //显示第二条内容
    showSecondDom() {
        this.setState((prevState, props) => {return {enableSecondDom: true}})
    }
}
```
在使用中，我们既可以通过指定``props``，也可以通过公有方法``showFirstDom()``、``showSecondDom()``，去改变``DynamicComponent``组件的UI样式。而对于这种动态改变着的UI组件，也是可以通过Snapshot进行快照比对，从而进行单元测试的。测试脚本例子如下：

```
import testRenderer from 'react-test-renderer';

describe('UI component snapshot test', () => {
    it('first test', () => {
        //第一步
        let treeObejct = testRenderer.create(<DynamicComponent
            title={'dynamic component snapshot test'}
            firstDomContext={'first dom context'}
            secondDomContext={'second dom context'} />)

        //第二步
        expect(treeObejct.toJSON()).toMatchSnapshot()

        //第三步
        treeObejct.getInstance().showFirstDom()
        expect(treeObejct.toJSON()).toMatchSnapshot()

        //第四步
        treeObejct.getInstance().showSecondDom()
        expect(treeObejct.toJSON()).toMatchSnapshot()
    })
})
```

其中：

- 第一步：指定``DynamicComponent``的props值，并新建一个相对应的序列化对象。
- 第二步：根据上一步中得到的序列化对象创建快照。可想而知，此时得到的快照是没有显示第一、第二条内容，而仅有title的。
- 第三步：通过序列化对象，获取组件实例。然后再通过得到的实例，调用公有方法，以显示第一条内容。最后，再次通过序列化对象创建这一步结束后的快照。此时的快照结果中，就会包含有title和第一条内容。
- 第四步：使用和第三步一样的方法，生成包含显示有第二条内容的快照。

那么这样的话，我们就可以得到这个动态UI组件每一步改变后的快照。因此，我们也就可以通过固化一些事件的路径，来测试UI组件有没有按照我们的预期去响应变化。
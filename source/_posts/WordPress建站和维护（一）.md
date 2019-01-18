---
title: WordPress建站和维护（一）
date: 2018-02-24 16:15:07
tags: [WordPress]
---

# 1、配置选择
centOS + nginx + php-fpm + mySQL + WordPress

# 2、安装
## 2.1、yum包管理器更新
执行``yum update``命令。

## 2.2、安装nginx
第一步：执行``yum install nginx``命令，安装最新版的nginx。

第二步：执行``service nginx start``命令，启动nginx服务。此时，如果安装成功，在浏览器中输入服务器IP地址，就可以看到nginx自带的欢迎页了。如果看不到的话，按照下面步骤排查常见的可能原因：

- 执行``service nginx status``命令，查看nginx服务是否正在运行中。

- 查看系统防火墙是否关闭，或者是否开放了80端口。7.0以上版本的centOS使用``firewall-cmd --state``命令，查看防火墙状态。使用``systemctl stop firewalld.service``或者``systemctl start firewalld.service``命令，停止/启动防火墙。其他的诸如开放个别端口，或者7.0以下版本设置方式，可以参照其他技术贴。

- 如果前两步排查结束后，仍然无法看到nginx欢迎页，而且服务器是云服务器的话，就需要排查是否在云服务器的安全组设置里，禁用了80端口。例如阿里云的默认安全组设置，就禁用了80端口，需要自己手动打开。

- 如果经过了上面三步的排查还不行，那啥也别说了，我只能传授给你重装+重启大法，你值得拥有。

- 如果还还还还不行的话，就只好good luck & God bless～

## 2.3、安装mySQL
第一步：执行``yum install mysql``命令，安装mysql。

第二步：执行``yum install mysql-server``命令，安装mysql-server。

- 如果此时出错并提示"无可用软件包mysql-server..."之类的，就执行下面的命令后重试：

```
	//可以进入http://repo.mysql.com，选择合适自己的rpm包版本链接
	wget http://repo.mysql.com/mysql-community-release-el5-5.noarch.rpm
	rpm -ivh mysql-community-release-el5-5.noarch.rpm
```
第三步：执行``service mysqld start``命令，开启mysql服务。**（注意：命令中是mysqld，多了一个d）**

## 2.4、安装php环境
第一步：执行``yum install -y php php-mysql php-gd libjpeg* php-imap php-ldap php-odbc php-pear php-xml php-xmlrpc php-mbstring php-mcrypt php-bcmath php-mhash libmcrypt libmcrypt-devel php-fpm``命令，安装php-fpm以及其他依赖的包。

第二步：执行``service php-fpm start``命令，开启php服务。

## 2.5、安装WordPress
第一步：执行``wget https://cn.wordpress.org/wordpress-4.9.4-zh_CN.tar.gz``命令，下载WordPress安装包。当然，为了保证是最新版本的安装包，也可以自己去官网上找到最新的下载链接并替换掉。

第二步：执行``tar -zxvf wordpress-4.9.4-zh_CN.tar.gz``命令解压安装包。

第三步：把解压后的所有文件，移到自己想要的位置，例如``/var/www/html``。

# 3、配置
## 3.1、数据库配置
第一步：执行``mysqladmin -u root password 123456``命令，创建一个名叫``root``，密码是``123456 ``的用户。

第二步：执行``mysql -u root -p``命令，使用刚才创建的用户连接上mySQL服务。

第三步：连接上了mySQL服务以后，就可以执行``CREATE DATABASE DATABASE_FOR_WORDPRESS;``命令，创建一个名叫``DATABASE_FOR_WORDPRESS ``的，用于存储WordPress数据的数据库表。

第四步：最后，执行``SHOW DATABASES;``命令，列出所有现存的数据库表，这样就能验证刚才的创建操作是不是真的成功了。

## 3.2、WordPress配置
进入刚才解压后的WordPress安装包路径（例如本例中的就是``/var/www/html``），打开wp-config.php文件，按照文件内的注释提示，填写好上一步中的各项数据库配置。

## 3.3、nginx配置
进入``/etc/nginx``路径中，找到nginx.conf文件并打开。

- ``location / {}``中的server_name，改为域名或者本机IP，或者干脆不动，先用默认的localhost。

- ``location / {}``中的root，改为解压后的WordPress安装包路径，本例中对应的就是``/var/www/html``。

- 在``location / {}``中的index那一行，添加``index.php``，以支持PHP类型的主页。

- 在和``location / {}``相同层级的位置上，添加下面一段配置，用以支持对PHP页面的解析。

```
location ~ .php$ {
	root /var/www/html;
	fastcgi_index index.php;
	fastcgi_pass 127.0.0.1:9000;
	fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
	include fastcgi_params;
}
```

- 执行``service nginx restart``命令，重启nginx服务。

此时，再在浏览器中输入服务器IP并打开，显示的就会是WordPress初始化页面了。不过，谁知道呢？也有可能看不到对不对，那假如真的没看到，当然肯定是又出错喽，所以good luck & God bless～

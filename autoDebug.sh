#!/bin/bash

echo Cleaning...
hexo clean

echo Generating...
hexo g

echo Local server staring...
hexo server
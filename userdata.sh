#!/bin/bash

yum install ansible  -y &>> /opt/userdata.log
ansible-pull -i localhost, -U https://github.com/hemanthtadikonda/UserInfoApp.git ${component}/main.yml -e component=${component} -e env=${env} &>> /opt/userdata.log
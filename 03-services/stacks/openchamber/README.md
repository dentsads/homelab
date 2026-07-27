# TODOS

Things to configure:
- ../../../data/workspaces chwon group to 1000 (sudo chown -R :1000 /data/workspaces)
- sudo find /data/workspaces -type d -exec chmod g+s {} +
- sudo apt update && sudo apt install acl -y
- sudo setfacl -R -d -m g::rwx /data/workspaces
- sudo setfacl -R -d -m u::rwx /data/workspaces
- add github connection
- add github identity
- mount ~/.ssh into container for git ssh certs. add public key to github ssh keys
- ssh-keyscan github.com >> ~/.ssh/known_hosts
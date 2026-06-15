# TODOS

Things to configure:
- ../../../data/workspaces chwon group to 1000 (sudo chown -R :1000 /data/workspaces)
- chmod g+s /data/workspaces
- sudo chmod -R g+w /data/workspaces
- add github connection
- add github identity
- mount ~/.ssh into container for git ssh certs. add public key to github ssh keys
- ssh-keyscan github.com >> ~/.ssh/known_hosts
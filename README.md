# vagrant
fsdeployer script for Vagrant.

This only for ```libvirt``` provider right now, sorry.
It shouldn't be hard to port that, maybe I'll do that in future.

To try it just do:

1. git clone https://github.com/jpazdyga/vagrant.git
2. cd vagrant
3. vagrant box add jpazdyga/coreos-alpha
4. vagrant init jpazdyga/coreos-alpha
5. mv Vagrantfile Vagrantfile.bkp
6. ./vagrant-appdeploy.sh testapp pazdyga.pl git@github.com:jpazdyga/testapp.git

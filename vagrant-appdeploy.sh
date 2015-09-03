#!/bin/bash

fetchip() {

	name="$1"
	for i in `sudo virsh list | grep running | grep $name| awk '{print $2}'`;
        do 
                qemumacaddr=`sudo virsh domiflist $i | grep network | awk '{print $5}'`
                ip=`sudo /sbin/arp -an | grep "$qemumacaddr" | awk '{print $2}' | sed -e 's/(//g' -e 's/)//g'`
        done

}

ansibledeploy() {

	vgtfilechk=`tail -1 Vagrantfile`
	if [[ "$vgtfilechk" =~ ^end ]];
	then
		echo "Removing the last 'end' statement from Vagrantfile."
		sed -i '$d' Vagrantfile
	else
		echo -e "Your Vagrantfile should contain the 'end' statement at it's end. Please try to fix that and come back.\nIf that's not possible we can't use autamatic ansible deployment for Vagrant, sorry.\nI'm sure you can sort it out manually."
		exit 1
	fi
	echo "Adding bits needed to deploy ansible server..."
	sleep $slpval
	echo -e "  config.vm.define \"ansible\" do |ansible|\n    ansible.vm.box = \"jpazdyga/coreos-alpha\"\n    ansible.vm.provision \"docker\" do |ans|\n      ans.run \"jpazdyga/ansible\",\n      args: \"-p \'2020:22\'\"\n    end\n  end\nend" >> Vagrantfile
	echo "Trying to spin up ansible.."
	vagrant up ansible --provider libvirt
	echo "That's done. Running tests again.."
	ansiblecheck

}

ansiblecheck() {
	
	echo -e "Using libvirt to guess your ansible server IP address."
	sleep $slpval
	fetchip ansible
	if [ ! -z $ip ];
	then
		echo "Libvirt based ansible server's IP address detected as $ip\. Good, let's proceed...\n"
		ansibleip="$ip"
		sleep $slpval
	fi

	echo "Checking reachability of $ansibleip using icmp echo request"
	sleep $slpval
	icmpresult=`ping -qn -i.4 -c5 -w1 $ansibleip | grep loss | cut -d' ' -f6 | sed 's/%//g'`
	if [ "$icmpresult" -eq "100" ];
	then
		echo -e "It seems your vagrant-based ansible server isn't responding to our icmp echo requests.\nIs it present in Vagrantfile? Let's find out..."
		sleep $slpval
		vgtans=`grep jpazdyga/ansible Vagrantfile 2>&1 > /dev/null; echo $?`
		if [ "$vgtans" -eq "0" ];
		then
			echo "Yes. It seems we're going to deploy ansible server as well, and that's all good..."
			sleep $slpval
		else
			read -p "Nope. Do you want me to deploy the ansible server as well? [y/n] " ansdeploy
			case $ansdeploy in
				y)
					sleep $slpval
					echo "Fine. Adding needed bits..."
					ansibledeploy
					sleep $slpva
				;;
				n)
					echo "Okay. Exiting now, bye."
					exit 1
				;;
				*)
					echo "No such possible answer exists."
				;;
			esac
		fi

	fi

	echo "Your vagrant-based ansible server seems to be reachable at $ansibleip and is icmp-reachable. Testing ssh connectivity now..."

	test=`nc -w1 -z $ansibleip $ansiblesshport ; echo $?`
	if [ "$test" -ne "0" ];
	then
		echo "Nope, ansible isn't reachable using ssh. Exiting."
		exit 1
	else
		ansibleresp=`$sshexec -p$ansiblesshport ansible@$ansibleip "ansible --version | grep ansible"`
		echo "Ansible version installed on server: $ansibleresp"
	fi
}

gitrepocheck() {

	giturlhttps=`echo "$giturl" | sed -e 's/github.com:/github.com\//g' -e 's/git@/https:\/\//g'`
	httpcode=`wget -q -O /dev/null -o /dev/null $giturlhttps; echo $?`
	if [ "$httpcode" -ne "0" ];
	then
		echo -e " \nGithub repository url you have specified is probably private.\n\n"
		read -p "Do you want to proceed using your [c]redentials, [t]oken or [q]uit? [c/t/q] " resp1
		case $resp1 in
			c)
				read -p "Enter your github usename: " username
				read -sp "Enter your github password: " password
				echo -e "\n"
				giturl=`echo $giturl | sed "s/:\/\//:\/\/$username:$password@/g"`
			;;
		 	t)
				giturl="$giturlhttps"
				read -p "Enter your application token: " token
				giturl=`echo $giturl | sed "s/:\/\//:\/\/$token@/g"`
			;;
			q)
				echo "Fine, exiting now."
				exit 0
			;;
			*)
				echo -e "Wrong answer given. Try again."
				gitrepocheck
			;;
		esac
	fi
}

createcloudconfig() {

        id_rsa=`$sshexec -p$ansiblesshport ansible@$ansibleip "cat /etc/ansible/.ssh/id_rsa.pub | cut -d' ' -f1,2"`

echo "#cloud-config

hostname: $shortname

ssh_authorized_keys:
 - ssh-rsa $authorizedkey

coreos:
 etcd2:
   discovery: https://discovery.etcd.io/$discovery" > ./cloud-config
   echo '   advertise-client-urls: http://$private_ipv4:2379,http://$private_ipv4:4001
   initial-advertise-peer-urls: http://$private_ipv4:2380
   listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
   listen-peer-urls: http://$private_ipv4:2380
 fleet:
   public-ip: $private_ipv4

users:
 - name: ansible
   groups:
     - sudo
     - docker
   ssh_authorized_keys:' >> ./cloud-config
echo "     - $id_rsa" >> ./cloud-config
}

defineandstart() {

	instanceid="$shortname"
	
	grep $instanceid Vagrantfile > /dev/null
	if [ "$?" -ne "0" ];
	then
		sed -i "s/^end/  config.vm.define \"$instanceid\" do \|$instanceid\|\n    $instanceid\.vm.box = \"jpazdyga\/coreos-alpha\"\n    $instanceid\.vm.provider :libvirt do \|domain\|\n      domain.memory = 2048\n      domain.cpus = 2\n    end\n    $instanceid.vm.provision :file, :source => \"cloud-config\", :destination => \"\/tmp\/vagrantfile-user-data\"\n    $instanceid.vm.provision :shell, :inline => \"mv \/tmp\/vagrantfile-user-data \/var\/lib\/coreos-vagrant\/\", :privileged => true\n  end\n\nend/g" Vagrantfile
	fi

	vagrant up $instanceid --provider libvirt
	if [ "$?" -ne "0" ]
	then
		echo "Instance not created. Exiting."
		exit 1
	fi
	sleep 5
	fetchip $instanceid
	privip="$ip"
	echo "Priv IP: " $privip

}

ansiblecreate() {
        $sshexec -t -p$ansiblesshport ansible@$ansibleip "sudo /usr/local/bin/add_new_coreos_host.sh $privip ; ansible-playbook coreos-bootstrap.yml ; ansible-playbook coreos-fsdeploy.yml --extra-vars 'giturl=$giturl domain=$domainname'"
	echo -e "\nYour code has been deployed. IP adress of the project is $privip.\n"

}

vmremove() {

	vagrant destroy $instanceid
        echo "machine removed"
        exit 0

}

if [ -z "$1" ];
then
	echo "Usage: $0 [server_shortname] [domainname] [giturl]"
        exit 1
elif [ "$1" == "remove" ];
then
        instanceid="$2"
        vmremove
fi

###     Things to be adjusted:  ###

# sleep command value to give the user time to read the output:
slpval=".4"

# Authorized keys for user 'core'
authorizedkey="AAAAB3NzaC1yc2EAAAABIwAAAQEAxLPLjUQf35uzbNGiCiVkOpeXOaO4JdC0GGkRTRhgSeKdu4Nz2iADET5bYBps27OCnk7JmWp3PiNbs6inMazHMylxB8BeV1Q9p+yMZLpuGdziokt4Z8sVDjgMkJPS0Ob74GE2aIfqx/gxTgf2WGQTNlCWP53nb3ccjQXW2b8jK39VCLw5VPE3YMojfGdM9BMhMOUdut3xnIJNnjivuZw9SZM746/PCvxvB/h+nE6u/3QP7D2xhEAXusxnctvOz2LWBf5rXrndAf4ENqOe6JK7LWGVTax2NgXc0pVJ53/+Ghhi2zYBuEaQGiOc7qeblJEUqrMXPij50LcE0ya10cmdAw=="

# generate a new token for each unique cluster from https://discovery.etcd.io/new?size=3
discovery="e730e50c6796a176fc93e3e602891291"

# CoreOS release to be installed:
rel="alpha"

# Virtual machine shortname
shortname="$1"

# Virtual machine domain:
domainname="$2"

# Machine short name (FQDN)
fqdn=`echo -e "$shortname.$domainname"`

ansibleip="192.168.121.56"
ansiblesshport="2020"

# Script's global ssh command
sshexec="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

if [ `echo $3 | grep git` ];
then
        giturl="$3"
else
	echo "You probably want to deploy an app from git repo. You'll need to specify git repo url for this."
	exit 1
fi

ansiblecheck
gitrepocheck
createcloudconfig
defineandstart
ansiblecreate

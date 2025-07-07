#cloud-config
#password id an output from mkpasswd --method=SHA-512 --rounds=4096
users:
  - name: ubuntu
    sudo: [sudo]
    shell: /bin/bash
    lock_passwd: false
    passwd: "{{ ubuntu_password | password_hash('sha512') }}"

package_update: true
package_upgrade: true
packages:
  - docker.io
  - docker-compose
  - git
  - curl

runcmd:
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ubuntu
  - curl -L https://downloads.portainer.io/ce2-20/portainer-agent-stack.yml -o /home/ubuntu/portainer-agent-stack.yml

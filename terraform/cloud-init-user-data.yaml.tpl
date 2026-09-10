#cloud-config
users:
  - name: ubuntu-${environment}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [sudo, docker]
    shell: /bin/bash
    lock_passwd: false
    passwd: "${ubuntu_password}"
    ssh_authorized_keys:
      - "${ubuntu_ssh_pub}"

package_update: true
package_upgrade: true
packages:
%{ if docker_enabled ~}
  - docker.io
  - docker-compose
%{ endif ~}
  - git
  - curl

runcmd:
%{ if docker_enabled ~}
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ubuntu-${environment}
  - curl -L https://downloads.portainer.io/ce2-20/portainer-agent-stack.yml -o /home/ubuntu-${environment}/portainer-agent-stack.yml
  - chown ubuntu-${environment}:ubuntu-${environment} /home/ubuntu-${environment}/portainer-agent-stack.yml
%{ endif ~}

#password id an output from mkpasswd --method=SHA-512 --rounds=4096
users:
  - name: brandon
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: false
    hashed_passwd: ${ubuntu_password}

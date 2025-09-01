# prep_evening1_en

**Date:** **2025-08-22**

**Topic:** Backlog.

**Daily goal:** Catch up on Day 1-2-3, review commands, do extra practice, and organize the repository.

---

## 1. Day 1-2-3 catch-up

### Tasks — Repeat Key Commands

Files and permissions:

`nano` — Opens/creates `file.txt` in the **nano** editor.

`cp` — Copies `file.txt` into a new file `copy.txt`.

`mv` — Renames/moves `copy.txt` to `moved.txt`.

`rm` — Deletes the file `moved.txt`.

---

`chmod 644` — Changes file permissions:

- owner = read/write;
- group and others = read only.

---

`touch` — Creates an empty file `script.sh`.

---

`chmod 755` — Makes `script.sh` executable:

- owner = read/write/execute;
- others = read/execute.

---

`sudo chown` — changes the owner of the file `file.txt` to the user `helpme`.

```bash
leprecha@Ubuntu-DevOps:~$ nano file.txt
leprecha@Ubuntu-DevOps:~$ cp file.txt copy.txt
leprecha@Ubuntu-DevOps:~$ mv copy.txt moved.txt
leprecha@Ubuntu-DevOps:~$ rm moved.txt
leprecha@Ubuntu-DevOps:~$ chmod 644 file.txt
leprecha@Ubuntu-DevOps:~$ touch script.sh
leprecha@Ubuntu-DevOps:~$ chmod 755 script.sh
leprecha@Ubuntu-DevOps:~$ sudo chown helpme file.txt
leprecha@Ubuntu-DevOps:~$ ls -l
-rw-r--r-- 1 helpme   sysadmin   14 Aug 22 19:43 file.txt
-rwxr-xr-x 1 leprecha sysadmin    0 Aug 22 19:44 script.sh
```

---

Networks:

`ping` — checks if a host is reachable. Sends echo requests and measures response time, showing whether the host is alive and how many ms it takes to reach it.

IPv4 → `ping -4`, IPv6 → `ping -6`

```bash
leprecha@Ubuntu-DevOps:~$ ping -c 4 google.com
PING google.com (2a00:1450:400b:c02::8b) 56 data bytes
64 bytes from dj-in-f139.1e100.net (2a00:1450:400b:c02::8b): icmp_seq=1 ttl=110 time=8.52 ms
64 bytes from dj-in-f139.1e100.net (2a00:1450:400b:c02::8b): icmp_seq=2 ttl=110 time=11.1 ms
64 bytes from dj-in-f139.1e100.net (2a00:1450:400b:c02::8b): icmp_seq=3 ttl=110 time=9.87 ms
64 bytes from dj-in-f139.1e100.net (2a00:1450:400b:c02::8b): icmp_seq=4 ttl=110 time=7.22 ms

--- google.com ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3004ms
rtt min/avg/max/mdev = 7.217/9.172/11.079/1.446 ms
```

---

`traceroute` — shows the path of a packet: which nodes the traffic passes through to reach the destination, listing intermediate routers and the time to each one.

```bash
leprecha@Ubuntu-DevOps:~$ traceroute google.com
traceroute to google.com (209.85.203.139), 30 hops max, 60 byte packets
 1  MyRouter.home (192.168.1.254)  4.627 ms  4.762 ms  7.338 ms
 2  95-44-248-1-dynamic.agg2.lky.bge-rtd.eircom.net (95.44.248.1)  5.401 ms  5.594 ms  5.803 ms
*
22  * dh-in-f139.1e100.net (209.85.203.139)  9.585 ms *
```

---

`dig` — a flexible tool for working with DNS. You can query any type of record (A, MX, NS, etc.).

```bash
leprecha@Ubuntu-DevOps:~$ dig google.com A

; <<>> DiG 9.18.30-0ubuntu0.24.04.2-Ubuntu <<>> google.com A
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 52445
;; flags: qr rd ra; QUERY: 1, ANSWER: 6, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 65494
;; QUESTION SECTION:
;google.com.			IN	A

;; ANSWER SECTION:
google.com.		3507	IN	A	209.85.203.101
google.com.		3507	IN	A	209.85.203.113
google.com.		3507	IN	A	209.85.203.102
google.com.		3507	IN	A	209.85.203.138
google.com.		3507	IN	A	209.85.203.139
google.com.		3507	IN	A	209.85.203.100

;; Query time: 1 msec
;; SERVER: 127.0.0.53#53(127.0.0.53) (UDP)
;; WHEN: Fri Aug 22 19:49:16 IST 2025
;; MSG SIZE  rcvd: 135
```

---

## 2. Mini-lab (combined)

- Create a folder `revision_lab`
- Inside it, make the structure `scripts,configs,logs,files,network`
- Create different files in `configs`
- Write `Hello World!` in the log
- In `files/` practice with `nano`, `chmod`, `chown`
- In `network/` save the outputs of `ping -c 4` google.com and `dig` google.com into files

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/revision_lab/{scripts,configs,logs,files,network}
leprecha@Ubuntu-DevOps:~$ touch revision_lab/configs/{nginx.conf,ssh_config}
leprecha@Ubuntu-DevOps:~$ echo "Hello World!"> ~/revision_lab/logs/startup.log
leprecha@Ubuntu-DevOps:~$ cd revision_lab/files
leprecha@Ubuntu-DevOps:~/revision_lab/files$ nano file.txt
leprecha@Ubuntu-DevOps:~/revision_lab/files$ chmod 644 file.txt
leprecha@Ubuntu-DevOps:~/revision_lab/files$ sudo chown helpme file.txt
leprecha@Ubuntu-DevOps:~/revision_lab/files$ ls -l
-rw-r--r-- 1 helpme sysadmin 11 Aug 22 19:52 file.txt
leprecha@Ubuntu-DevOps:~/revision_lab/files$ cd ..
leprecha@Ubuntu-DevOps:~/revision_lab$ cd network
leprecha@Ubuntu-DevOps:~/revision_lab/network$ ping -c 4 google.com | tee ping.txt
PING google.com (2a00:1450:400b:c02::8b) 56 data bytes
64 bytes from dj-in-f139.1e100.net (2a00:1450:400b:c02::8b): icmp_seq=1 ttl=110 time=7.47 ms
64 bytes from dj-in-f139.1e100.net (2a00:1450:400b:c02::8b): icmp_seq=2 ttl=110 time=9.95 ms
64 bytes from dj-in-f139.1e100.net (2a00:1450:400b:c02::8b): icmp_seq=3 ttl=110 time=9.29 ms
64 bytes from dj-in-f139.1e100.net (2a00:1450:400b:c02::8b): icmp_seq=4 ttl=110 time=7.80 ms

--- google.com ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3004ms
rtt min/avg/max/mdev = 7.474/8.628/9.948/1.024 ms
leprecha@Ubuntu-DevOps:~/revision_lab/network$ dig google.com > dig.txt
```

---

## 3. Day 4 overview

| Command / File | Purpose |
| --- | --- |
| `adduser` | Create a new user |
| `userdel` | Delete a user (`-r` also removes home directory) |
| `usermod` | Modify user settings (groups, shell, home dir, etc.) |
| `groups` | Show user’s groups |
| `id` | Display UID, GID and groups |
| `whoami` | Show current username |
| `/etc/passwd` | User accounts (login, UID, GID, shell) |
| `/etc/group` | Groups (name, GID, members) |
| `/etc/shadow` | Password hashes and aging policy |

---

## 4. Basic user management commands

`adduser` — Creates a new user.

```bash
leprecha@Ubuntu-DevOps:~$ sudo adduser helpme_second
info: Adding user `helpme_second' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `helpme_second' (1002) ...
info: Adding new user `helpme_second' (1002) with group `helpme_second (1002)' ...
info: Creating home directory `/home/helpme_second' ...
info: Copying files from `/etc/skel' ...
New password: 
passwd: password updated successfully
Changing the user information for helpme_second
Enter the new value, or press ENTER for the default
	Full Name []: Borya Koryavui
	Room Number [23]: 
	Work Phone [6543]: 
	Home Phone [5678]: 
	Other []: 
Is the information correct? [Y/n] Y
info: Adding new user `helpme_second' to supplemental / extra groups `users' ...
info: Adding user `helpme_second' to group `users' ...
```

---

`userdel` — Deletes a user.

```bash
leprecha@Ubuntu-DevOps:~$ sudo userdel -r helpme_second
```

---

`usermod` — Modifies parameters of an existing user.

```bash
leprecha@Ubuntu-DevOps:~$ sudo usermod -aG sudo helpme
leprecha@Ubuntu-DevOps:~$ id helpme
uid=1001(helpme) gid=1001(helpme) groups=1001(helpme),27(sudo),100(users)
```

---

`groups` — Shows which groups a user belongs to.

```bash
leprecha@Ubuntu-DevOps:~$ groups
sysadmin adm cdrom sudo dip plugdev users lpadmin
leprecha@Ubuntu-DevOps:~$ groups helpme
helpme : helpme users
```

---

`id` — Displays the UID (user ID), GID (group ID), and groups.

```bash
leprecha@Ubuntu-DevOps:~$ id leprecha
uid=1000(leprecha) gid=1000(sysadmin) groups=1000(sysadmin),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),100(users),114(lpadmin)
leprecha@Ubuntu-DevOps:~$ id helpme
uid=1001(helpme) gid=1001(helpme) groups=1001(helpme),100(users)
```

---

`whoami` — Shows the name of the current user.

```bash
leprecha@Ubuntu-DevOps:~$ whoami
leprecha
```

---

## 5. System user files

`/etc/passwd` — List of users. Each line = one user.

```bash
leprecha@Ubuntu-DevOps:~$ tail -n 5 /etc/passwd
nm-openvpn:x:121:122:NetworkManager OpenVPN,,,:/var/lib/openvpn/chroot:/usr/sbin/nologin
leprecha:x:1000:1000:leprecha:/home/leprecha:/bin/bash
helpme:x:1001:1001:Ivan Ivanov,1,12345,67890:/home/helpme:/bin/bash
nvidia-persistenced:x:122:124:NVIDIA Persistence Daemon,,,:/nonexistent:/usr/sbin/nologin
_flatpak:x:123:125:Flatpak system-wide installation helper,,,:/nonexistent:/usr/sbin/nologin

#tail -n 5 — prints the last 5 lines.
```

**Fields:**

- **username** → `leprecha` — the user’s login.
- **password** → `x` → means the password is stored in `/etc/shadow`.
- **UID** → `1000` → unique user ID (usually the first "regular" user after system installation).
- **GID** → `1000` → group ID with the same name `leprecha`.
- **comment** → `leprecha` → comment/description (often contains full name, job title).
- **home_directory** → `/home/leprecha` → the user’s home directory.
- **shell** → `/bin/bash` → default shell.

---

`/etc/group` — List of all groups.

`grep` — Check all groups where `leprecha` appears.

```bash
leprecha@Ubuntu-DevOps:~$ grep leprecha /etc/group
adm:x:4:syslog,leprecha
cdrom:x:24:leprecha
sudo:x:27:leprecha
dip:x:30:leprecha
plugdev:x:46:leprecha
users:x:100:leprecha,helpme
lpadmin:x:114:leprecha
```

- **group_name** → `sudo`
- **x** → password not used
- **GID** → `27`
- **members** → `leprecha`

---

The user `leprecha` is included in the `sudo` group and can use `sudo` for administrative commands.

`/etc/shadow` — file with passwords and their policies (protected, accessible only to root).

```bash
leprecha@Ubuntu-DevOps:~$ sudo tail -n 5 /etc/shadow
nm-openvpn:!:20305::::::
leprecha:$6$PHoDNHyS2Nt3ciZv$0V9A9r1qJ1//ezypKwDLXexPAPyYxWfvOS.Lqy6NU86xIv4abUjLzazl8yPAylmHRlzwH2ymBLjg8RHDfu99d.:20319:0:99999:7:::
helpme:$y$j9T$OQiW82n0NBtTCOExcwVI0.$WGVKyAq.QSJxv06avKIiqz8apDBq2GaMaXCHKo7VB4C:20320:0:99999:7:::
nvidia-persistenced:!:20321::::::
_flatpak:!:20321::::::
```

- `leprecha` → username.
- **`$6$...`** → password hash, algorithm **SHA-512** (`$6$`).
- **`20319`** → day of the last password change, counted from January 1, 1970.
    
    (20319 days = July 2025).
    
- **`0`** → minimum number of days before password can be changed (can be changed daily).
- **`99999`** → maximum number of days the password is valid (essentially unlimited).
- **`7`** → system will start warning 7 days before expiration.
- Remaining fields empty (`:::`) → no restrictions on account lock or lifetime.

---

## 6. Extra Linux practice

### Practice:

1. Create a directory `extra_practice` with folders `private`, `shared`.
2. In `private/`, make a file that only the owner can read and edit.
3. In `shared/`, make a script that any user can run.
4. Check the permissions.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/extra_practice/{private,shared}
leprecha@Ubuntu-DevOps:~$ echo "secret" > ~/extra_practice/private/secret.txt
leprecha@Ubuntu-DevOps:~$ chmod 600 ~/extra_practice/private/secret.txt
leprecha@Ubuntu-DevOps:~$ cat <<'EOF' > ~/extra_practice/shared/run.sh
#!/bin/bash
echo Hello my Lady
EOF
leprecha@Ubuntu-DevOps:~$ chmod 755 ~/extra_practice/shared/run.sh
leprecha@Ubuntu-DevOps:~$ ls -l ~/extra_practice/{private,shared}
/home/leprecha/extra_practice/private:
-rw------- 1 leprecha sysadmin 7 Aug 22 20:16 secret.txt
/home/leprecha/extra_practice/shared:
-rwxr-xr-x 1 leprecha sysadmin 31 Aug 22 20:16 run.sh
leprecha@Ubuntu-DevOps:~$ ~/extra_practice/shared/run.sh
Hello my Lady
```

`cat > file << 'EOF'` — everything between the first `EOF` and the second `EOF` will be written into the file.

---

## Result: All done, backlog cleared, ready for Day 4.
# CATS: Programming contest control system

## Overview

CATS is a software for managing programming problems, organizing competitions,
and supporting continuous learning process of programming-related subjects.

## Docker

Set environment variables inside `.env.local`:
```
cp .env .env.local
```

Setup `venv` for python script:
```
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Installation on Linux

To install CATS you need to have `git` and `sudo` installed:

`# apt-get install git sudo`

Make sure current user is in `sudoers` (sudo group).

Clone this repo:

`$ git clone git://github.com/klenin/cats-main.git`

Look at `deploy.bash`, adjust `http_proxy` (and set `env_keep` in `/etc/sudoers`,
see comments in `deploy.bash`) and Apache user group. Then execute the script:

`$ ./deploy.bash`

Restart Apache. You should now have working CATS installation.
Visit `http://localhost/cats/` to check.

## Installation on Windows

Clone this repo:

`> git clone git://github.com/klenin/cats-main.git`

Run deploy script:

`> deploy.bat`

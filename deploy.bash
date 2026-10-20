#!/usr/bin/env bash
# user, that executes this script must be in sudo group

#parse command line
step="*"

while [[ $# -gt 1 ]]; do
	key=$1
	case $key in 
	-s|--step)
		step="$2"
		shift
	;;
	*)
		echo 'Unknown option: '
		tail -1 $key
		exit
	;;
	esac
	shift
done
if [[ -n $1 ]]; then
	echo "Last option not have argument: "
	tail -1 $1
	exit
fi

CATS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # assume, that script is in a root dir of repo

# PROXY USERS, PLEASE READ THIS
# If your network is behind proxy please uncomment and set following variables
#export http_proxy=host:port
#export https_proxy=$http_proxy
#export ftp_proxy=$http_proxy
#
# You also NEED to replace following line in /etc/sudoers:
# Defaults        env_reset
# With:
# Defaults env_keep="http_proxy https_proxy ftp_proxy"

# Group, apache running under
http_group=www-data

echo "1. Install apt packages... "
if [[ $step =~ (^|,)1(,|$)  || $step == "*" ]]; then
	packages+=(
		git unzip wget build-essential
		libaspell-dev aspell-en aspell-ru
		libhunspell hunspell-en hunspell-ru
		apache2 libapache2-mod-perl2 libapreq2-3 libapreq2-dev
		libapache2-mod-perl2-dev libexpat1 libexpat1-dev libapache2-request-perl cpanminus)
	sudo apt-get -y install ${packages[@]}
	echo "ok"
else
	echo "skip"
fi

echo "2. Install cpan packages... "
if [[ $step =~ (^|,)2(,|$) || $step == "*" ]]; then
	cpan_packages=(
		Module::Install
		DBI
		DBI::Profile
		DBD::Pg
		Algorithm::Diff
		Archive::Zip
		Authen::Passphrase
		File::Copy::Recursive
		JSON::XS
		SQL::Abstract
		Template
		Test::Exception
		Text::Aspell
		Text::CSV
		Text::Hunspell
		Text::MultiMarkdown
		XML::Parser::Expat
	)
	# Apache2::Request is intentionally not installed via cpanm: building it
	# from the libapreq2 CPAN tarball fails to configure against this box's
	# Apache dev headers. libapache2-request-perl (apt, step 1) already
	# provides the same Perl bindings, prebuilt against the correct headers.
	sudo cpanm --notest -S ${cpan_packages[@]}
	echo "ok"
else
	echo "skip"
fi

echo "3. Install formal input... "
if [[ $step =~ (^|,)3(,|$) || $step == "*" ]]; then
	# FormalInput's source, https://github.com/downloads/klenin/cats-main/FormalInput.tgz,
	# is a GitHub "downloads" link, a feature GitHub removed around 2012; the
	# URL 404s and there is no known replacement source yet. It's an optional
	# soft dependency (cgi-bin/cats-problem/CATS/Problem/Parser.pm degrades
	# gracefully if it's missing), so skip rather than fail the whole script.
	echo "skip (dead upstream URL, see comment in deploy.bash)"
else
	echo "skip"
fi

echo "4. Generating docs... "
if [[ $step =~ (^|,)4(,|$) || $step == "*" ]]; then
	cd docs/tt
	ttree -f ttreerc
	cd $CATS_ROOT
	echo "ok"
else
	echo "skip"
fi

echo "5. Configure Apache... "
if [[ $step =~ (^|,)5(,|$) || $step == "*" ]]; then
APACHE_CONFIG=$(cat <<EOF
PerlSetEnv CATS_DIR ${CATS_ROOT}/cgi-bin/
<VirtualHost *:80>
	PerlRequire ${CATS_ROOT}/cgi-bin/CATS/Web/startup.pl
	<Directory "${CATS_ROOT}/cgi-bin/">
		Options -Indexes
		LimitRequestBody 1048576
		Require all granted
		PerlSendHeader On
		SetHandler perl-script
		PerlResponseHandler main
	</Directory>
	ExpiresActive On
	ExpiresDefault "access plus 5 seconds"
	ExpiresByType text/css "access plus 1 week"
	ExpiresByType application/javascript "access plus 1 week"
	ExpiresByType image/gif "access plus 1 week"
	ExpiresByType image/png "access plus 1 week"
	ExpiresByType image/x-icon "access plus 1 week"

	Alias /cats/static/css/ "${CATS_ROOT}/css/"
	Alias /cats/static/ "${CATS_ROOT}/static/"
	<Directory "${CATS_ROOT}/static">
		# Apache allows only absolute URL-path
		ErrorDocument 404 /cats/?f=static
		#Options FollowSymLinks
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	Alias /cats/download/ "${CATS_ROOT}/download/"
	<Directory "${CATS_ROOT}/download">
		Options -Indexes
		Require all granted
		AddCharset utf-8 .txt
	</Directory>

	Alias /cats/docs/ "${CATS_ROOT}/docs/"
	<Directory "${CATS_ROOT}/docs">
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	Alias /cats/junior/ "${CATS_ROOT}/junior/"
	<Directory "${CATS_ROOT}/ev">
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	Alias /cats/css/ "${CATS_ROOT}/css/"
	<Directory "${CATS_ROOT}/css/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
		Require all granted
	</Directory>

	Alias /favicon.ico "${CATS_ROOT}/images/favicon.ico"
	Alias /cats/images/ "${CATS_ROOT}/images/"
	<Directory "${CATS_ROOT}/images/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
		Require all granted
	</Directory>   

	Alias /cats/js/ "${CATS_ROOT}/js/"
	<Directory "${CATS_ROOT}/js/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
		Require all granted
	</Directory>

	Alias /cats/ "${CATS_ROOT}/cgi-bin/"
	Alias /cats "${CATS_ROOT}/cgi-bin/"
</VirtualHost>
EOF
)
	
	sudo sh -c "echo '$APACHE_CONFIG' > /etc/apache2/sites-available/000-cats.conf"
	sudo a2ensite 000-cats
	sudo a2dissite 000-default
	sudo a2enmod expires
	sudo a2enmod apreq2
	sudo a2dismod mpm_event
	sudo a2enmod mpm_prefork

	echo "ServerName localhost" | sudo tee /etc/apache2/conf-available/servername.conf
	sudo a2enconf servername

	# Adjust permissions.
	sudo chgrp -R ${http_group} cgi-bin css download images static tt
	chmod -R g+r cgi-bin
	chmod g+rw static tt download/{,att,f,img,pr,vis} cgi-bin/rank_cache{,/r} cgi-bin/repos
#	sudo service apache2 reload
#	sudo service apache2 restart
	echo "ok"
else
	echo "skip"
fi

echo "6. Download JS... "
if [[ $step =~ (^|,)6(,|$) || $step == "*" ]]; then
    perl -e 'install_js.pl --install=all'
	cd $CATS_ROOT
	echo "ok"
else
	echo "skip"
fi


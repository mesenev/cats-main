FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update && apt-get install -y gnupg

RUN apt-get install -y \
    sudo dnsutils \
    wget \
    curl \
    git \
    build-essential \
    libaspell-dev aspell-en aspell-ru \
    libhunspell-dev hunspell-en-us hunspell-ru \
    apache2 libapache2-mod-perl2 libapreq2-3 libapreq2-dev \
    libapache2-mod-perl2-dev libexpat1 libexpat1-dev libapache2-request-perl \
    cpanminus postgresql libpq-dev \
    && apt-get clean

RUN cpanm --notest \
    Module::Install DBI DBI::Profile DBD::Pg Algorithm::Diff \
    Archive::Zip Authen::Passphrase File::Copy::Recursive \
    JSON::XS SQL::Abstract Template Test::Exception Text::Aspell Text::CSV \
    Text::Hunspell Text::MultiMarkdown XML::Parser::Expat
# Apache2::Request is intentionally not installed via cpanm: building it from
# the libapreq2 CPAN tarball fails to configure against this image's Apache
# dev headers. libapache2-request-perl (apt, above) already provides the
# same Perl bindings, prebuilt against the correct headers.

# FormalInput (optional: cgi-bin/cats-problem/CATS/Problem/Parser.pm soft-requires
# it and degrades gracefully if missing) is intentionally not installed here.
# Its source, https://github.com/downloads/klenin/cats-main/FormalInput.tgz, is a
# GitHub "downloads" link, a feature GitHub removed around 2012; the URL 404s.
# deploy.bash's own step 3 has the identical dead link, silently swallowed there
# since that script has no `set -e`. Needs a real fix (new source/mirror) later.

# App code (cgi-bin, css, js, static, download, images, docs, tt) is bind-mounted
# into /app at runtime, not baked into the image. The vhost only needs the path
# layout, not the files themselves, so it can be set up at build time.
COPY dockerfiles/main/000-cats.conf /etc/apache2/sites-available/000-cats.conf
RUN a2ensite 000-cats && a2dissite 000-default \
    && a2enmod expires && a2enmod apreq2 \
    && a2dismod mpm_event && a2enmod mpm_prefork \
    && echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf && a2enconf servername \
    && ln -sf /proc/self/fd/1 /var/log/apache2/error.log

WORKDIR /app
EXPOSE 80

CMD ["apachectl", "-D", "FOREGROUND"]

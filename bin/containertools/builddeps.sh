#!/bin/bash

set -e

cat > /etc/yum.repos.d/kurl.local.repo <<EOF
[kurl.local]
name=kURL Local Repo
baseurl=file:///packages/archives
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF

# list first level dependency provides
available_packages="$(yum -q --disablerepo=* --enablerepo=kurl.local --releasever=/ --installroot=/tmp/empty-directory list available \
    | grep -v "Available Packages" | awk '{ print $1 }' | sed 's/\.x86_64//')"
depslist="$(echo "$available_packages" \
    | xargs -L1 yum -q --enablerepo=kurl.local deplist --arch=x86_64 --arch=noarch --resolve --requires \
    | awk 'NF{NF-=2}1' FS='-' OFS='-')" # strip last two fields

# some packages may list both libcurl and libcurl-minimal, meaning one or the
# other. we are aware of some cases where some packages explicitly require
# libcurl-minimal. if the package requires one or the other we will prefer
# minimal.
hascurl=false
hascurlminimal=false
for package in $depslist; do
    if [ "$package" = "libcurl" ]; then
        hascurl=true
    elif [ "$package" = "libcurl-minimal" ]; then
        hascurlminimal=true
    fi
done
if $hascurl && $hascurlminimal; then
    depslist="$(printf '%s\n' $depslist | sed 's/^libcurl$//g')"
fi

# some packages may list both openssl-snapsafe-libs and openssl-libs, we are
# going with openssl-libs.
depslist="$(printf '%s\n' $depslist | sed 's/openssl-snapsafe-libs/openssl-libs/g')"

for package in $available_packages ; do
    # remove packages that in the first level dependency provides
    depslist="$(echo "$depslist" | grep -v "^$package$")"
done
echo "$depslist"

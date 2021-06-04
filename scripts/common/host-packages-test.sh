#!/bin/bash

set -e

. ./scripts/common/host-packages.sh

function test_yum_filter_host_packages() {
    function yum() {
        echo "Available Packages
cairo.x86_64                                                                       1.15.12-4.el7                                                                   kurl.local
collectd.x86_64                                                                    5.8.1-1.el7                                                                     kurl.local
collectd-rrdtool.x86_64                                                            5.8.1-1.el7                                                                     kurl.local
dejavu-fonts-common.noarch                                                         2.33-6.el7                                                                      kurl.local
dejavu-sans-fonts.noarch                                                           2.33-6.el7                                                                      kurl.local
dejavu-sans-mono-fonts.noarch                                                      2.33-6.el7                                                                      kurl.local
fontconfig.x86_64                                                                  2.13.0-4.3.el7                                                                  kurl.local
fontpackages-filesystem.noarch                                                     1.44-8.el7                                                                      kurl.local
fribidi.x86_64                                                                     1.0.2-1.el7_7.1                                                                 kurl.local
graphite2.x86_64                                                                   1.3.10-1.el7_3                                                                  kurl.local
harfbuzz.x86_64                                                                    1.7.5-2.el7                                                                     kurl.local
libX11.x86_64                                                                      1.6.7-3.el7_9                                                                   kurl.local
libX11-common.noarch                                                               1.6.7-3.el7_9                                                                   kurl.local
libXau.x86_64                                                                      1.0.8-2.1.el7                                                                   kurl.local
libXdamage.x86_64                                                                  1.1.4-4.1.el7                                                                   kurl.local
libXext.x86_64                                                                     1.3.3-3.el7                                                                     kurl.local
libXfixes.x86_64                                                                   5.0.3-1.el7                                                                     kurl.local
libXft.x86_64                                                                      2.3.2-2.el7                                                                     kurl.local
libXrender.x86_64                                                                  0.9.10-1.el7                                                                    kurl.local
libXxf86vm.x86_64                                                                  1.1.4-1.el7                                                                     kurl.local
libglvnd.x86_64                                                                    1:1.0.1-0.8.git5baa1e5.el7                                                      kurl.local
libglvnd-egl.x86_64                                                                1:1.0.1-0.8.git5baa1e5.el7                                                      kurl.local
libglvnd-glx.x86_64                                                                1:1.0.1-0.8.git5baa1e5.el7                                                      kurl.local
libthai.x86_64                                                                     0.1.14-9.el7                                                                    kurl.local
libwayland-client.x86_64                                                           1.15.0-1.el7                                                                    kurl.local
libwayland-server.x86_64                                                           1.15.0-1.el7                                                                    kurl.local
libxcb.x86_64                                                                      1.13-1.el7                                                                      kurl.local
libxshmfence.x86_64                                                                1.2-1.el7                                                                       kurl.local
mesa-libEGL.x86_64                                                                 18.3.4-12.el7_9                                                                 kurl.local
mesa-libGL.x86_64                                                                  18.3.4-12.el7_9                                                                 kurl.local
mesa-libgbm.x86_64                                                                 18.3.4-12.el7_9                                                                 kurl.local
mesa-libglapi.x86_64                                                               18.3.4-12.el7_9                                                                 kurl.local
pango.x86_64                                                                       1.42.4-4.el7_7                                                                  kurl.local
pixman.x86_64                                                                      0.34.0-1.el7                                                                    kurl.local
rrdtool.x86_64                                                                     1.4.8-9.el7                                                                     kurl.local
yajl.x86_64                                                                        2.0.4-4.el7                                                                     kurl.local"
    }
    export yum

    assertEquals "yum_filter_host_packages kurl.local collectd collectd-rrdtool collectd-disk" "collectd collectd-rrdtool" "$(yum_filter_host_packages kurl.local collectd collectd-rrdtool collectd-disk)"
}

. shunit2

package MT::Plugin::SyncedTheme::Util;

use strict;
use warnings;
use utf8;

our @EXPORT = qw(plugin);
use base qw(Exporter);

sub plugin {
    MT->component('SyncedTheme');
}

1;

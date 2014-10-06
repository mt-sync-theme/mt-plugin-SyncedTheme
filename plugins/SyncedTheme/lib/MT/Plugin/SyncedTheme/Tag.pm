package MT::Plugin::SyncedTheme::Tag;

use strict;
use warnings;
use utf8;

sub if_synced_theme_link_template {
    my $blog = MT->instance->blog
        or return 0;

    $blog->synced_theme_link_template;
}

1;


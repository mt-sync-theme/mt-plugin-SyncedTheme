package MT::Plugin::SyncedTheme::Theme;

use strict;
use warnings;
use utf8;

use MT::Plugin::SyncedTheme::Blog;

sub post_apply_theme {
    my ( $cb, $theme, $blog ) = @_;

    MT::Plugin::SyncedTheme::Blog->link_template( $blog, 1 )
        if $blog->synced_theme_link_template;
}

1;

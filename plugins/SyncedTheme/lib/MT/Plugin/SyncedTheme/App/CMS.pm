package MT::Plugin::SyncedTheme::App::CMS;

use strict;
use warnings;
use utf8;

use MT::Plugin::SyncedTheme::Util;
use MT::Plugin::SyncedTheme::Blog;

sub param_edit_blog {
    my ( $cb, $app, $param, $tmpl ) = @_;

    my $anchor = $tmpl->getElementById('blog_language');
    foreach my $t ( @{ plugin()->load_tmpl('edit_blog.tmpl')->tokens } ) {
        $tmpl->insertAfter( $t, $anchor );
        $anchor = $t;
    }
}

sub param_refresh_templates {
    my ( $cb, $app, $param, $tmpl ) = @_;

    my $anchor = $tmpl->getElementById('clean_start');
    foreach
        my $t ( @{ plugin()->load_tmpl('refresh_templates.tmpl')->tokens } )
    {
        $tmpl->insertAfter( $t, $anchor );
        $anchor = $t;
    }
}

sub param_export_theme {
    my ( $cb, $app, $param, $tmpl ) = @_;

    my $anchor = $tmpl->getElementById('theme-output-field')->parentNode;
    foreach my $t ( @{ plugin()->load_tmpl('export_theme.tmpl')->tokens } ) {
        $tmpl->insertAfter( $t, $anchor );
        $anchor = $t;
    }
}

sub source_theme_export_replace {
    my ( $cb, $app, $tmpl ) = @_;

    my $html = '';
    for my $k (qw(synced_theme_link_template synced_theme_assign_theme_id)) {
        $html
            .= qq{<input type="hidden" name="$k" value="@{[$app->param($k) ? '1' : '0']}" />};
    }
    $$tmpl =~ s{(</form>)}{$html\n$1};
}

1;

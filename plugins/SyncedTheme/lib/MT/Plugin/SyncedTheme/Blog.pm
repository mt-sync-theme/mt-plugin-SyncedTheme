package MT::Plugin::SyncedTheme::Blog;

use strict;
use warnings;
use utf8;

use File::Spec;
use Cwd qw(abs_path);

sub pre_save {
    my ( $cb, $blog ) = @_;

    my $app = MT->instance;

    return unless $app->can('param');

    if ( defined( $app->param('synced_theme_link_template') ) ) {
        $blog->synced_theme_link_template(
            scalar $app->param('synced_theme_link_template') );
    }

    if ( $app->param('synced_theme_assign_theme_id') ) {
        if ( my $theme_id = $app->param('theme_id') ) {
            $blog->theme_id($theme_id);
        }
    }
}

sub post_save {
    my ( $cb, $blog ) = @_;
    __PACKAGE__->link_template($blog);
}

sub link_template {
    my $class = shift;
    my ( $blog, $force ) = @_;

    my $app = MT->instance;

    return
        unless $force
        || ( $app->can('param')
        && $app->param('synced_theme_link_template') );

    my $theme     = $blog->theme;
    my $templates = $theme->{elements}{template_set}{data}{templates};
    my $base_path
        = $theme->{elements}{template_set}{data}{base_path} || 'templates';

    for my $tmpl ( MT->model('template')->load( { blog_id => $blog->id } ) ) {
        my $identifier = $tmpl->identifier
            or next;

        my ($hash) = grep {$_}
            map { $templates->{$_}{$identifier} } keys %$templates;
        next unless $hash;

        my $file
            = File::Spec->catfile( $theme->path, $base_path,
            $hash->{filename} || ( $identifier . '.mtml' ) );

        next
            unless abs_path($file) =~ m/\A@{[abs_path($theme->path)]}/
            && -e abs_path($file);

        $tmpl->linked_file($file);
        $tmpl->save or die;
    }
}

1;

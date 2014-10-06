package MT::Plugin::SyncedTheme::App::DataAPI;

use strict;
use warnings;
use utf8;

use File::Spec;
use File::Basename qw(basename dirname);
use Cwd qw(abs_path);

use MT::Theme;
use MT::CMS::Template;

my %action_map = (
    'preview'             => \&_action_preview,
    'on-the-fly'          => \&_action_on_the_fly,
    'apply-page'          => \&_action_apply_page,
    'apply-pref'          => \&_action_apply_pref,
    'apply-category'      => \&_action_apply_category,
    'apply-folder'        => \&_action_apply_folder,
    'apply-template-set'  => \&_action_apply_template_set,
    'apply-static-files'  => \&_action_apply_static_files,
    'apply-custom-fields' => \&_action_apply_custom_fields,
    'rebuild'             => \&_action_rebuild,
);

sub _theme {
    my ($app) = @_;

    my ($id) = $app->param('theme_id')
        or return;

    MT::Theme->load($id)
        or MT::Theme->new(
        id   => $id,
        path => File::Spec->catdir( MT->config('ThemesDirectory'), $id ),
        );
}

sub _unserialize {
    my ($name) = @_;
    my $app = MT->instance;

    my $raw_value = $app->param($name)
        or return;

    eval { $app->current_format->{unserialize}->($raw_value) }
        or die 'Invalid request';
}

sub _preview_target_template_objects {
    my ( $app, $theme, $updated_files, $requires_fileinfo ) = @_;

    my %identifiers = ();

    my @blogs = $app->model('blog')->load(
        {   class    => '*',
            theme_id => $theme->id,
        }
    ) or return [];

    my $templates = $theme->{elements}{template_set}{data}{templates};
    my $template_base_path = abs_path(
        File::Spec->catfile(
            $theme->path,
            $theme->{elements}{template_set}{data}{base_path} || 'templates'
        )
    );

    my @updated_template_files
        = grep { $_ =~ m/\A$template_base_path/ } @$updated_files;

    my $find_template;
    $find_template = sub {
        my ($filename) = @_;
        ( my $identifier = $filename ) =~ s/\.mtml\z//;

        my ( $id, $hash ) = sub {
            for my $hashes ( values %{$templates} ) {
                for my $id ( keys %{$hashes} ) {
                    my $hash = $hashes->{$id};
                    if ( my $fn = $hash->{filename} ) {
                        return ( $id, $hash ) if $filename eq $fn;
                    }
                    else {
                        return ( $id, $hash ) if $id eq $identifier;
                    }
                }
            }
            }
            ->();

        if ( $hash->{preview_via} ) {
            return $find_template->( $hash->{preview_via} . '.mtml' );
        }
        else {
            return $id;
        }
    };
    for my $f (@updated_template_files) {
        my $filename = basename($f);
        my $id = $find_template->($filename) or next;

        $identifiers{$id} = 1;
    }

    return [] unless %identifiers;

    my @tmpls = $app->model('template')->load(
        {   blog_id => [ map { $_->id } @blogs ],
            type       => [qw(index archive individual page)],
            identifier => [ keys %identifiers ],
        },
        {   (   $requires_fileinfo
                ? ( joins => [
                        MT->model('fileinfo')->join_on(
                            'template_id',
                            undef,
                            {   unique => 1,
                                type   => 'inner'
                            },
                        )
                    ]
                    )
                : ()
            ),
            sort      => 'blog_id',
            direction => 'descend',
        }
    );
    my %tmpls = map { $_->identifier => $_ } @tmpls;
    return [ values %tmpls ];
}

sub _action_preview {
    my ( $app, $theme, $updated_files ) = @_;

    my $templates = _preview_target_template_objects(@_);

    my $theme_templates = $theme->{elements}{template_set}{data}{templates};
    my $template_base_path = abs_path(
        File::Spec->catfile(
            $theme->path,
            $theme->{elements}{template_set}{data}{base_path} || 'templates'
        )
    ) . '_preview';

    my @urls;
    {
        no warnings 'redefine';

        my $original_config = MT->can('config');
        local *MT::config = sub {
            my $self = shift;
            my ($key) = @_;
            ( $key && lc($key) eq 'previewinnewwindow' )
                ? 1
                : $self->$original_config(@_);
        };

        local *MT::App::redirect = sub {
            my $self = shift;
            my ($url) = @_;
            push @urls, $url;
        };

        local *MT::App::validate_magic = sub {
            1;
        };

        require MT::App::CMS;
        local *MT::App::DataAPI::preview_object_basename
            = \&MT::App::CMS::preview_object_basename;

        local *MT::Template::_sync_to_disk = sub {
            1;
        };

        local *MT::Template::_sync_from_disk = sub {
            my ($self) = shift;
            my $linkded_file = $self->linked_file;
            if ( $linkded_file && -e $linkded_file ) {
                do { open my $fh, '<', $linkded_file; local $/; scalar <$fh> };
            }
            else {
                return;
            }
        };

        local *MT::Template::linked_file = sub {
            my ($self) = shift;

            $self->{synced_theme_linked_template} ||= sub {
                for my $hashes ( values %{$theme_templates} ) {
                    if ( my $hash = $hashes->{ $self->identifier } ) {
                        my $file = abs_path(
                            File::Spec->catfile(
                                $template_base_path,
                                $hash->{filename}
                                    || ( $self->identifier . '.mtml' )
                            )
                        );
                        last
                            unless $file
                            && $file =~ m/\A@{[abs_path($theme->path)]}/
                            && -e $file;
                        return $file;
                    }
                }

                return $self->column_values->{linked_file};
                }
                ->();
        };

        for my $tmpl (@$templates) {
            my $blog = local $app->{_blog} = $tmpl->blog;
            local $app->{query} = CGI->new(
                {   blog_id => $blog->id,
                    %{ $tmpl->column_values },
                }
            );
            MT::CMS::Template::preview($app);
        }
    };

    +{ urls => \@urls, };
}

sub _action_on_the_fly {
    my ( $app, $theme, $updated_files ) = @_;

    my $templates = _preview_target_template_objects( @_, 0 );

    return +{} unless @$templates;

    my %blogs
        = ( map { $_->id => $_ }
            $app->model('blog')
            ->load( { id => [ map { $_->blog_id } @$templates ], } ) );
    my %tmpls = ( map { $_->id => $_ } @$templates );

    my @infos = $app->model('fileinfo')
        ->load( { template_id => [ keys %tmpls ], }, );

    my @urls;
    for my $fi (@infos) {
        $app->publisher->rebuild_from_fileinfo($fi);
        my $blog = $blogs{ $fi->blog_id };
        my $tmpl = $tmpls{ $fi->template_id };
        (   my $host
                = $tmpl->type eq 'index'
            ? $blog->site_url
            : $blog->archive_url
        ) =~ s{(.*?//[^/]+).*}{$1};
        my $url = $host . $fi->url;
        push @urls, $url;
    }

    +{ urls => \@urls, };
}

sub _action_filtered_apply {
    my ( $importer, $app, $theme, $updated_files ) = @_;

    my @blogs = $app->model('blog')->load(
        {   class    => '*',
            theme_id => $theme->id,
        }
    );

    for my $b (@blogs) {
        $theme->apply( $b, importer_filter => { $importer => 1 } );
    }

    +{};
}

sub _action_apply_page {
    my ( $app, $theme, $updated_files ) = @_;
    _action_filtered_apply( 'default_pages', @_ );
}

sub _action_apply_pref {
    my ( $app, $theme, $updated_files ) = @_;
    _action_filtered_apply( 'default_prefs', @_ );
}

sub _action_apply_category {
    my ( $app, $theme, $updated_files ) = @_;
    _action_filtered_apply( 'default_categories', @_ );
}

sub _action_apply_folder {
    my ( $app, $theme, $updated_files ) = @_;
    _action_filtered_apply( 'default_folders', @_ );
}

sub _action_apply_template_set {
    my ( $app, $theme, $updated_files ) = @_;
    _action_filtered_apply( 'template_set', @_ );
}

sub _action_apply_static_files {
    my ( $app, $theme, $updated_files ) = @_;
    _action_filtered_apply( 'blog_static_files', @_ );
}

sub _action_apply_custom_fields {
    my ( $app, $theme, $updated_files ) = @_;
    _action_filtered_apply( 'custom_fields', @_ );
}

sub _action_rebuild {
    my ( $app, $theme, $updated_files ) = @_;

    my @blogs = $app->model('blog')->load(
        {   class    => '*',
            theme_id => $theme->id,
        }
    );

    for my $b (@blogs) {
        $app->rebuild( Blog => $b );
    }

    +{};
}

sub _post_files_handler {
    my ( $app, $endpoint ) = @_;

    my $user = $app->user;
    $app->error(403)
        unless $user->can_do('edit_templates');

    my $theme = _theme(@_)
        or return;

    my $files = _unserialize('files');
    my $actions = _unserialize('actions') || [];

    die 'The "files" parameter is required and can take ARRAY'
        unless $files && ref $files eq 'ARRAY';

    my $fmgr = MT::FileMgr->new('Local');
    $fmgr->mkpath( $theme->path ) unless $fmgr->exists( $theme->path );
    $fmgr->can_write( $theme->path )
        or die 'Not writable: ' . $theme->path;

    my @updated_files;
    my $abs_theme_path = File::Spec->rel2abs( $theme->path );
    for my $f (@$files) {
        next unless $f->{path};

        my $path
            = File::Spec->rel2abs(
            File::Spec->catfile( $theme->path, $f->{path} ) );

        next unless $path =~ m/\A$abs_theme_path/;

        if ( $f->{action} eq 'put' ) {
            $fmgr->mkpath( dirname($path) );
            $fmgr->put_data( $f->{content}, $path );

            push @updated_files, $path;
        }
        elsif ( $f->{action} eq 'delete' ) {
            $fmgr->delete($path);
        }
    }

    # Reload
    MT::Theme->load_all_themes;
    $theme = MT::Theme->load( $theme->id )
        or die MT::Theme->errstr;

    my %result = ( actions => [], );

    for my $a (@$actions) {
        my $handler = $action_map{$a}
            or die 'Unknown action: ' . $a;
        my $res = $handler->( $app, $theme, \@updated_files );
        $res->{action} = $a;
        push @{ $result{actions} }, $res;
    }

    \%result;
}

sub post_files {
    my ( $app, $endpoint ) = @_;

    eval { _post_files_handler(@_) } or $app->errstr && () or do {
        my $e = $@;
        $e =~ s/\s+at\s.*//s;
        $app->error($e);
    };
}

1;

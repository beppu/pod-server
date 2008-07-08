package Pod::Server;
use base 'Squatting';
our $VERSION = '1.02';
our %CONFIG = (
  background_color         => '#112',
  foreground_color         => 'wheat',
  pre_background_color     => '#000',
  pre_foreground_color     => '#ccd',
  code_foreground_color    => '#fff',
  a_foreground_color       => '#fc4',
  a_hover_foreground_color => '#fe8',
  font_size                => '10pt',
  sidebar                  => 'right',
  first                    => 'Squatting',
  title                    => '#',
);

package Pod::Server::Controllers;
use Squatting ':controllers';
use File::Basename;
use File::Find;
use Config;

# skip files we've already seen
my %already_seen;

# figure out where all(?) our pod is located
# (loosely based on zsh's _perl_basepods and _perl_modules)
our %perl_basepods = map {
  my ($file, $path, $suffix) = fileparse($_, ".pod");
  $already_seen{$_} = 1;
  ($file => $_);
} glob "$Config{installprivlib}/pod/*.pod";

our %perl_modules;
our @perl_modules;
sub scan {
  no warnings;
  for (@INC) {
    next if $_ eq ".";
    my $inc = $_;
    my $pm_or_pod = sub {
      my $m = $File::Find::name;
      next if -d $m;
      next unless /\.(pm|pod)$/;
      next if $already_seen{$m};
      $already_seen{$m} = 1;
      $m =~ s/$inc//;
      $m =~ s/\.\w*$//;
      $m =~ s{^/}{};
      $perl_modules{$m} = $File::Find::name;
    };
    find({ wanted => $pm_or_pod, follow_fast => 1 }, $_);
  }
  my %h = map { $_ => 1 } ( keys %perl_modules, keys %perl_basepods );
  @perl_modules = sort keys %h;
}
scan;
%already_seen = ();

# *.pod takes precedence over *.pm
sub pod_for {
  for ($_[0]) {
    return $_ if /\.pod$/;
    my $pod = $_;
    $pod =~ s/\.pm$/\.pod/;
    if (-e $pod) {
      return $pod;
    }
    return $_;
  }
}

# *.pm takes precedence over *.pod
sub code_for {
  for ($_[0]) {
    return $_ if /\.pm$/;
    my $pm = $_;
    $pm =~ s/\.pod$/\.pm/;
    if (-e $pm) {
      return $pm;
    }
    return $_;
  }
}

# cat out a file
sub cat {
  my $file = shift;
  open(CAT, $file) || return;
  return join('', <CAT>);
}

our @C = (

  C(
    Home => [ '/' ],
    get  => sub {
      my ($self) = @_;
      $self->v->{title} = $Pod::Server::CONFIG{title};
      if ($self->input->{base}) {
        $self->v->{base} = 'pod';
      }
      $self->render('home');
    }
  ),

  C(
    Frames => [ '/@frames' ],
    get    => sub {
      my ($self) = @_;
      $self->v->{title} = $Pod::Server::CONFIG{title};
      $self->render('_frames');
    }
  ),

  C(
    Source => [ '/@source/(.*)' ],
    get => sub {
      my ($self, $module) = @_;
      my $v = $self->v;
      $v->{path} = [ split('/', $module) ];
      my $pm_file;
      if (exists $perl_modules{$module}) {
        $pm_file = code_for $perl_modules{$module};
        $v->{code} = cat $pm_file;
        $self->render('source');
      } elsif (exists $perl_basepods{$module}) {
        $pm_file = code_for $perl_basepods{$module};
        $v->{code} = cat $pm_file;
        $self->render('source');
      } else {
        $v->{title} = "Pod::Server - $pm";
        $self->render('pod_not_found');
      }
    }
  ),

  # The job of this controller is to take $module
  # and find the file that contains the POD for it.
  # Then it asks the view to turn the POD into HTML.
  C(
    Pod => [ '/(.*)' ],
    get => sub {
      my ($self, $module) = @_;
      my $v        = $self->v;
      my $pm       = $module; $pm =~ s{/}{::}g;
      $v->{path}   = [ split('/', $module) ];
      $v->{module} = $module;
      $v->{pm}     = $pm;
      if (exists $perl_modules{$module}) {
        $v->{pod_file} = pod_for $perl_modules{$module};
        $v->{title} = "$Pod::Server::CONFIG{title} - $pm";
        $self->render('pod');
      } elsif (exists $perl_basepods{$module}) {
        $v->{pod_file} = pod_for $perl_basepods{$module};
        $v->{title} = "Pod::Server - $pm";
        $self->render('pod');
      } else {
        $v->{title} = "$Pod::Server::CONFIG{title} - $pm";
        $self->render('pod_not_found');
      }
    }
  ),

);

package Pod::Server::Views;
use Squatting ':views';
use Data::Dump 'pp';
use HTML::AsSubs;
use Pod::Simple;
use Pod::Simple::HTML;
$Pod::Simple::HTML::Perldoc_URL_Prefix = '/';

# the ~literal pseudo-element -- don't entity escape this content
sub x {
  HTML::Element->new('~literal', text => $_[0])
}

our $JS;
our $HOME;
our $C = \%Pod::Server::CONFIG;

our @V = (
  V(
    'html',

    layout => sub {
      my ($self, $v, @content) = @_;
      html(
        head(
          title($v->{title}),
          style(x($self->_css)),
          (
            $v->{base} 
              ? base({ target => $v->{base} })
              : ()
          ),
        ),
        body(
          div({ id => 'menu' },
            a({ href => R('Home')}, "Home"), ($self->_breadcrumbs($v))
          ),
          div({ id => 'pod' }, @content),
        ),
      )->as_HTML;
    },

    _breadcrumbs => sub {
      my ($self, $v) = @_;
      my @breadcrumb;
      my @path;
      for (@{$v->{path}}) {
        push @path, $_;
        push @breadcrumb, a({ href => R('Pod', join('/', @path)) }, " > $_ ");
      }
      @breadcrumb;
    },

    _css => sub {
      qq|
        body {
          background: $C->{background_color};
          color: $C->{foreground_color};
          font-family: 'Trebuchet MS', sans-serif;
          font-size: $C->{font_size};
        }
        h1, h2, h3, h4 {
          margin-left: -1em;
        }
        pre {
          font-size: 9pt;
          background: $C->{pre_background_color};
          color: $C->{pre_foreground_color};
        }
        code {
          font-size: 9pt;
          font-weight: bold;
          color: $C->{code_foreground_color};
        }
        a {
          color: $C->{a_foreground_color};
          text-decoration: none;
        }
        a:hover {
          color: $C->{a_hover_foreground_color};
        }
        div#menu {
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          background: #000;
          color: #fff;
          opacity: 0.75;
        }
        ul#list {
          margin-left: -6em;
          list-style: none;
        }
        div#pod {
          width: 580px;
          margin: 2em 4em 2em 4em;
        }
        div#pod pre {
          padding: 0.5em;
          border: 1px solid #444;
          -moz-border-radius-bottomleft: 7px;
          -moz-border-radius-bottomright: 7px;
          -moz-border-radius-topleft: 7px;
          -moz-border-radius-topright: 7px;
        }
        div#pod h1 {
          font-size: 24pt;
          border-bottom: 2px solid $C->{a_hover_foreground_color};
        }
        div#pod p {
          line-height: 1.4em;
        }
      |;
    },

    home => sub {
      $HOME ||= div(
        a({ href => R(Home),   target => '_top' }, "no frames"),
        em(" | "),
        a({ href => R(Frames), target => '_top' }, "frames"),
        ul({ id => 'list' },
          map {
            my $pm = $_;
            $pm =~ s{/}{::}g;
            li(
              a({ href => R('Pod', $_) }, $pm )
            )
          } (sort @perl_modules)
        )
      );
    },

    _frames => sub {
      my ($self, $v) = @_;
      html(
        head(
          title($v->{title})
        ),
        ($C->{sidebar} eq "right" 
          ?
          frameset({ cols => '*,340' },
            frame({ name => 'pod',  src => R('Pod', $C->{first}) }),
            frame({ name => 'list', src => R('Home', { base => 'pod' }) }),
          )
          :
          frameset({ cols => '340,*' },
            frame({ name => 'list', src => R('Home', { base => 'pod' }) }),
            frame({ name => 'pod',  src => R('Pod', $C->{first}) }),
          )
        ),
      )->as_HTML;
    },

    pod => sub {
      my ($self, $v) = @_;
      my $out;
      my $pod = Pod::Simple::HTML->new;
      $pod->index(1);
      $pod->output_string($out);
      $pod->parse_file($v->{pod_file});
      $out =~ s{%3A%3A}{/}g;
      $out =~ s/^.*<!-- start doc -->//s;
      $out =~ s/<!-- end doc -->.*$//s;
      x($out), 
      $self->_possibilities($v),
      $self->_source($v);
    },

    pod_not_found => sub {
      my ($self, $v) = @_;
      div(
        p("POD for $v->{pm} not found."),
        $self->_possibilities($v)
      )
    },

    _possibilities => sub {
      my ($self, $v) = @_;
      my @possibilities = grep { /^$v->{module}/ } @perl_modules;
      my $colon = sub { my $x = shift; $x =~ s{/}{::}g; $x };
      hr,
      ul(
        map {
          li(
            a({ href => R('Pod', $_) }, $colon->($_))
          )
        } @possibilities
      );
    },

    _source => sub {
      my ($self, $v) = @_;
      hr,
      h4( a({ href => R('Source', $v->{module} )}, "Source Code for " . Pod::Server::Controllers::code_for($v->{pod_file}) ) );
    },

    source => sub {
      my ($self, $v) = @_;
      style("div#pod { width: auto; }"), 
      pre($v->{code});
    },

  )
);

1;

__END__

=head1 NAME

Pod::Server - a web server for locally installed perl documentation

=head1 SYNOPSIS

Usage for the pod_server script:

  pod_server [OPTION]...

Examples:

  pod_server --help

  pod_server -bg '#301'

Then, in your browser, visit:

  http://localhost:8088/

How to start up a Continuity-based server manually (via code):

  use Pod::Server 'On::Continuity';
  Pod::Server->init;
  Pod::Server->continue(port => 8088);

How to embed Pod::Server into a Catalyst app:

  use Pod::Server 'On::Catalyst';
  Pod::Server->init;
  Pod::Server->relocate('/pod');
  $Pod::Simple::HTML::Perldoc_URL_Prefix = '/pod/';
  sub pod : Local { Pod::Server->catalyze($_[1]) }

=head1 DESCRIPTION

In the Ruby world, there is a utility called C<gem_server> which starts up a
little web server that serves documentation for all the locally installed
RubyGems.  When I was coding in Ruby, I found it really useful to know what
gems I had installed and how to use their various APIs.

"Why didn't Perl have anything like this?"

Well, apparently it did.  If I had searched through CPAN, I might have found
L<Pod::Webserver> which does the same thing this module does.

However, I didn't know that at the time, so I ended up writing this module.
At first, its only purpose was to serve as an example L<Squatting> app, but
it felt useful enough to spin off into its own perl module distribution.

I have no regrets about duplicating effort or reinventing the wheel, because
Pod::Server has a lot of nice little features that aid usability and readability.
It is also quite configurable.  To see all the options run either of the following:

  pod_server -h

  squatting Pod::Server --show-config

=head2 My one regret...

Well, OK.  I have one regret.  I didn't know that L<Pod::Simple::Search>
existed.  I would've used that to build the list of all the POD on the system
had I known about it sooner than just now (2008-07-06).  This just goes to show
that it's hard to know what's on CPAN, let alone your own system.  I guess you
really have to develop the habit of looking.


=head1 SEE ALSO

L<Squatting>, L<Continuity>, L<Pod::Webserver>

=head1 AUTHOR

John BEPPU E<lt>beppu@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (c) 2008 John BEPPU E<lt>beppu@cpan.orgE<gt>.

=head2 The "MIT" License

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

=cut

package Mod::Test;
use Mod::Generic;
use Mod::Fill;
use DB_File;
use strict;
use vars qw(@ISA %paragraph %command %comment_table %escape);

@ISA = 'Mod::Generic';



%paragraph = (
              'whitespace' => sub {""},
              'prose' => sub {""},
              'program' => \&program,
              'command' => sub {""},
             );

%command =
  (
   'starttest' => \&test,
   'test' => \&test,
   'endtest' => \&test,
   'auxtest' => \&test,
   'testable' => \&test,
   'inline_testcode' => \&inline,

   'stop' => \&Stop,
  );

################################################################


# Override generic versions
sub open_output_file {
  my ($self, $in) = @_;
  my $out = $in;
  $out =~ s/\.\w+$/.tst/ or $out .= ".tst";
  my $fh;
  unless (open $fh, ">", $out) {
    die "Couldn't open test list file '$out' for writing: $!\n";
  }
  $self->{test_list_fh} = $fh;
  warn "Reading '$in'...\n";
}
sub output { }

sub init {
  my $self = shift;
  $self->{progdir} = $ENV{PROGDIR} || "Programs";
  $self->{testdir} = $ENV{TESTDIR} || "Tests";
  $self->{comment} = 0;
  $self->{indentstr} = '  ';
  $self->{extra_indent} = '';
  $self->{prog_indent} = "    ";
  $self->{test} = 0;
  $self->{tests} = {};
  $self->{test_fh} = undef;
  $self->{testno} = "test1";
}

my %saw;

sub inline {
  my ($self, $tag, $text, $file, @args) = @_;
  my $fh = $self->{test_fh};
  unless ($fh) {
    $self->warning("$tag directive outside test code");
    return "";
  }
  my $in;
  unless (open $in, "<", "$self->{testdir}/$file") {
    $self->warning("Couldn't read inlined test code from '$file'");
    return "";
  }
  print $fh $_ while <$in>;
}

sub test {
  my ($self, $tag, $text, $testname, $n_tests, @args) = @_;
  $testname = $self->{testno}++ unless defined $testname;
  if ($tag eq "test" || $tag eq "starttest" ||
      $tag eq "auxtest" || $tag eq "testable") {
    my $testfile = $testname;
    my $AUX = $tag if $tag eq "auxtest" || $tag eq "testable";
    $self->{AUX} = $AUX;
    unless ($AUX) {
      $testfile .= ".t" unless $testfile =~ /\.t$/;
    }
    $testfile = "$self->{testdir}/$testfile"
      unless $testfile =~ m{/};
    if ($saw{$testfile}++) {
      $self->warning("Repeated test file name '$testfile'");
    }

    my $fh;
    unless (open $fh, ">", $testfile) {
      warn "Couldn't open file '$testfile' for writing: $!; skipping";
      return;
    }
    warn $AUX ? "Writing auxiliary file '$testname'\n"
              : "Writing test '$testname'\n" ;
    $self->{test_fh} = $fh;
    unless ($AUX) {
      my $plan = defined($n_tests) ? "tests => $n_tests" : "'no_plan'";
      print $fh "\n# test '$testname'\n\n";
      print $fh "use Test::More $plan;\n";
      print $fh "use lib '$self->{progdir}';\n";
      print $fh "use lib '$self->{testdir}';\n";
      print $fh "alarm(5) unless \$^P;\n\n";
      my $start_line = $self->{line}+2; # ???
#      print $fh "#line $start_line $self->{infilename}\n";
#      print $fh "#line 1 $testfile\n";
    }

    if ($self->{test}) {
      warn "'$tag' tag on line $self->{line} nested in '$self->{start_test_tag}' section starting on line $self->{start_test_line}";
    }
    $self->{start_test_tag} = $tag;
    $self->{start_test_line} = $self->{line};
    $self->{test_name} = $testname;
    $self->{tests}{$testname} = $testfile unless $AUX;
    $self->{test} = 1;
  } elsif ($tag eq "endtest") {
    unless ($self->{test}) {
      $self->warning("Unmatched '$tag' tag");
      return;
    }
    my $fh = $self->{test_fh};
    print $fh "\n1;\n\n" if $self->{AUX} eq "auxtest";
    close $fh;
    $self->{test} = 0;
  } else {
    $self->warning("Unknown testing tag '$tag'");
  }
}

sub program {
  my ($self, $text, @args) = @_;
  return unless $self->{test};

  my $true_text = $text;
  $true_text =~ s/^\t/        /mg;
  my $prefix = $self->{prefix};
  unless (defined ($prefix)) {
    ($prefix) = ($true_text =~
                 m{\A(\ +).*      # First line with its prefix
                    (?:\n          # first line's newline
                     (?:\1.*\n     # subsequent lines, with same prefix
                       |\s*\n)*    #   or perhaps they're just empty
                     (?:\1.*\n?    # final line, possibly without trailer
                       |\s*$)      #   or perhaps it's just empty
                    )?             # there might be only one line
                    \z}x);
    $self->{prefix} = $prefix;
  }

  # Trim off prefix
  my @lines = split /^/, $true_text;
  {
    local $_;
    for (@lines) {
      s/^$prefix//;
    }
  }


  my $fh = $self->{test_fh};
  print $fh $true_text;
  "";
}

sub Stop {
  return '', Stop => 1;
}

sub DESTROY {
  my $self = shift;
  my $tests = $self->{tests};
  my $fh = $self->{test_list_fh};
  for my $testfile (values %$tests) {
    print $fh "$testfile\n";
  }
  close $fh;
}

1;


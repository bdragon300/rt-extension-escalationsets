use inc::Module::Install;

RTx 'RT-Extension-EscalationSets';
license 'perl';
author 'Igor Derkach <gosha753951@gmail.com>';
version '0.1';

build_requires('Test::More');
requires 'Date::Manip' => '6.25';
requires_rt('4.0.0');
auto_install();

my ($lp) = ($INC{'RT.pm'} =~ /^(.*)[\\\/]/);
my $lib_path = join( ' ', "$RT::LocalPath/lib", $lp );
my $sbin_path = $RT::SbinPath || "$RT::BasePath/sbin" || "/opt/rt3/sbin";
my $bin_path = $RT::BinPath || "$RT::BasePath/bin" || "/opt/rt3/bin";

substitute(
    {
        RT_LIB_PATH  => $lib_path,
        RT_BIN_PATH  => $bin_path,
        RT_SBIN_PATH => $sbin_path,
    },
    {
        sufix => '.in',
    },
    qw(
        lib/RT/Extension/EscalationSets/Test.pm
        lib/RT/Extension/EscalationSets/TestFunc.pm
        lib/RT/Extension/EscalationSets/MockTransaction.pm
        lib/RT/Extension/EscalationSets/Sample_SiteConfig.pm
    ),
);
tests 'xt/*.t xt/*/*.t';

sign;
&WriteAll;
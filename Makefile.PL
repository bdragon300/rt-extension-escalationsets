use inc::Module::Install;

RTx 'RT-Extension-EscalationSets';
license 'perl';
author 'Igor Derkach <gosha753951@gmail.com>';
version '0.1';

requires 'Date::Manip' => '6.25';
requires_rt('4.0.0');
auto_install();

sign;
&WriteAll;
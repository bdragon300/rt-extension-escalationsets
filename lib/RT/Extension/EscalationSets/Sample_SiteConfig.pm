Set($EscalationField, 'escalation_level');
Set($EscalationSetField, 'Escalation set');
Set(%EscalationSets, ('RFI'        => { '1' => {due => '-846 minutes'},
                                        '2' => {due => '-564 minutes'},
                                        '3' => {due => '-282 minutes'},
                                        '_due' => {created => '94 hours'},
                                        '_default_level' => '0'
                                      },
                      'RFS'        => { '1' => {due => '-288 minutes'},
                                        '2' => {due => '-192 minutes'},
                                        '3' => {due => '-96 minutes'},
                                        '_due' => {created => '32 hours'},
                                        '_default_level' => '0'
                                      },
                      'Incident10' => { '1' => {due => '-180 minutes'},
                                        '2' => {due => '-108 minutes'},
                                        '3' => {due => '-36 minutes'},
                                        '_due' => {created => '12 hours'},
                                        '_default_level' => '0'
                                      },
                      'Incident20' => { '1' => {due => '-75 minutes'},
                                        '2' => {due => '-45 minutes'},
                                        '3' => {due => '-15 minutes'},
                                        '_due' => {created => '5 hours'},
                                        '_default_level' => '0'
                                      },
                      'Incident30' => { '1' => {due => '-60 minutes'},
                                        '2' => {due => '-30 minutes'},
                                        '3' => {due => '-12 minutes'},
                                        '_due' => {created => '2 hours'},
                                        '_default_level' => '0'
                                      },
                      'Incident40' => { '1' => {due => '-24 minutes'},
                                        '2' => {due => '-12 minutes'},
                                        '3' => {due => '-5 minutes'},
                                        '_due' => {created => '48 minutes'},
                                        '_default_level' => '0'
                                      }
));

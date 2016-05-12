Set($EscalationField, 'escalation_level');
Set($EscalationSetField, 'Escalation set');
Set(%EscalationSets, ('RFI'       => {
                                        'levels' => {
                                            '1' => {due => '-846 minutes'},
                                            '2' => {due => '-564 minutes'},
                                            '3' => {due => '-282 minutes'},
                                        },
                                    'due' => {created => '94 hours'},
                                    'default_level' => '0'
                                    },
                      'RFS'        => {
                                        'levels' => {
                                            '1' => {due => '-288 minutes'},
                                            '2' => {due => '-192 minutes'},
                                            '3' => {due => '-96 minutes'},
                                        },
                                        'due' => {created => '32 hours'},
                                        'default_level' => '0'
                                      },
                      'Incident10' => {
                                        'levels' => {
                                            '1' => {due => '-180 minutes'},
                                            '2' => {due => '-108 minutes'},
                                            '3' => {due => '-36 minutes'},
                                        },
                                        'due' => {created => '12 hours'},
                                        'default_level' => '0'
                                      },
                      'Incident20' => {
                                        'levels' => {
                                            '1' => {due => '-75 minutes'},
                                            '2' => {due => '-45 minutes'},
                                            '3' => {due => '-15 minutes'},
                                        },
                                        'due' => {created => '5 hours'},
                                        'default_level' => '0'
                                      },
                      'Incident30' => {
                                        'levels' => {
                                            '1' => {due => '-60 minutes'},
                                            '2' => {due => '-30 minutes'},
                                            '3' => {due => '-12 minutes'},
                                        },
                                        'due' => {created => '2 hours'},
                                        'default_level' => '0'
                                      },
                      'Incident40' => {
                                        'levels' => {
                                            '1' => {due => '-24 minutes'},
                                            '2' => {due => '-12 minutes'},
                                            '3' => {due => '-5 minutes'},
                                        },
                                        'due' => {created => '48 minutes'},
                                        'default_level' => '0'
                                      },
));

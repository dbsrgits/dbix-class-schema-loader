package DBIx::Class::TestRSComponent;
use base qw/DBIx::Class::ResultSet/;

sub dbix_class_testrscomponent : ResultSet { 'dbix_class_testrscomponent works' }

1;

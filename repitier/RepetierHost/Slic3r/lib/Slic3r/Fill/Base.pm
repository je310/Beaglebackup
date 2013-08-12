package Slic3r::Fill::Base;
use Moo;

use Slic3r::Geometry qw(PI);

has 'layer_id'            => (is => 'rw');
has 'angle'               => (is => 'rw', default => sub { $Slic3r::Config->fill_angle });
has 'bounding_box'        => (is => 'ro', required => 1);

sub angles () { [0, PI/2] }

sub infill_direction {
    my $self = shift;
    my ($surface) = @_;
    
    # set infill angle
    my (@rotate, @shift);
    $rotate[0] = Slic3r::Geometry::deg2rad($self->angle);
    $rotate[1] = Slic3r::Geometry::bounding_box_center($self->bounding_box);
    @shift = @{$rotate[1]};
    
    if (defined $self->layer_id) {
        # alternate fill direction
        my $layer_num = $self->layer_id / $surface->thickness_layers;
        my $angle = $self->angles->[$layer_num % @{$self->angles}];
        $rotate[0] = Slic3r::Geometry::deg2rad($self->angle) + $angle if $angle;
    }
        
    # use bridge angle
    if (defined $surface->bridge_angle) {
        Slic3r::debugf "Filling bridge with angle %d\n", $surface->bridge_angle;
        $rotate[0] = Slic3r::Geometry::deg2rad($surface->bridge_angle);
    }
    
    @shift = @{ +(Slic3r::Geometry::rotate_points(@rotate, \@shift))[0] };
    return [\@rotate, \@shift];
}

# this method accepts any object that implements rotate() and translate()
sub rotate_points {
    my $self = shift;
    my ($expolygon, $rotate_vector) = @_;
    
    # rotate points
    $expolygon->rotate(@{$rotate_vector->[0]});
    $expolygon->translate(@{$rotate_vector->[1]});
}

sub rotate_points_back {
    my $self = shift;
    my ($paths, $rotate_vector) = @_;
    my @rotate = (-$rotate_vector->[0][0], $rotate_vector->[0][1]);
    my $shift  = [ map -$_, @{$rotate_vector->[1]} ];
    
    @$paths = map [ Slic3r::Geometry::rotate_points(@rotate, @$_) ], 
        map [ Slic3r::Geometry::move_points($shift, @$_) ], @$paths;
}

sub adjust_solid_spacing {
    my $self = shift;
    my %params = @_;
    
    my $number_of_lines = int($params{width} / $params{distance}) + 1;
    return $params{distance} if $number_of_lines <= 1;
    
    my $extra_space = $params{width} % $params{distance};
    return $params{distance} + $extra_space / ($number_of_lines - 1);
}

1;

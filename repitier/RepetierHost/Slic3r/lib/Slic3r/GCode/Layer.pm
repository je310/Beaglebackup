package Slic3r::GCode::Layer;
use Moo;

use List::Util qw(first);
use Slic3r::Geometry qw(X Y unscale);

has 'print'                         => (is => 'ro', required => 1, handles => [qw(extruders)]);
has 'gcodegen'                      => (is => 'ro', required => 1);
has 'shift'                         => (is => 'ro', required => 1);

has 'spiralvase'                    => (is => 'lazy');
has 'skirt_done'                    => (is => 'rw', default => sub { {} });  # print_z => 1
has 'brim_done'                     => (is => 'rw');
has 'second_layer_things_done'      => (is => 'rw');
has '_last_obj_copy'                => (is => 'rw');

sub _build_spiralvase {
    my $self = shift;
    
    return $Slic3r::Config->spiral_vase
        ? Slic3r::GCode::SpiralVase->new
        : undef;
}

sub process_layer {
    my $self = shift;
    my ($layer, $object_copies) = @_;
    my $gcode = "";
    
    if (!$self->second_layer_things_done && $layer->id == 1) {
        for my $t (grep $self->extruders->[$_], 0 .. $#{$Slic3r::Config->temperature}) {
            $gcode .= $self->gcodegen->set_temperature($self->extruders->[$t]->temperature, 0, $t)
                if $self->print->extruders->[$t]->temperature && $self->extruders->[$t]->temperature != $self->extruders->[$t]->first_layer_temperature;
        }
        $gcode .= $self->gcodegen->set_bed_temperature($Slic3r::Config->bed_temperature)
            if $Slic3r::Config->bed_temperature && $Slic3r::Config->bed_temperature != $Slic3r::Config->first_layer_bed_temperature;
        $self->second_layer_things_done(1);
    }
    
    # set new layer, but don't move Z as support material contact areas may need an intermediate one
    $gcode .= $self->gcodegen->change_layer($layer);
    
    # prepare callback to call as soon as a Z command is generated
    $self->gcodegen->move_z_callback(sub {
        $self->gcodegen->move_z_callback(undef);  # circular ref or not?
        return "" if !$Slic3r::Config->layer_gcode;
        return $Slic3r::Config->replace_options($Slic3r::Config->layer_gcode) . "\n";
    });
    
    # extrude skirt
    if ((values %{$self->skirt_done}) < $Slic3r::Config->skirt_height && !$self->skirt_done->{$layer->print_z}) {
        $self->gcodegen->set_shift(@{$self->shift});
        $gcode .= $self->gcodegen->set_extruder($self->extruders->[0]);  # move_z requires extruder
        $gcode .= $self->gcodegen->move_z($layer->print_z);
        # skip skirt if we have a large brim
        if ($layer->id < $Slic3r::Config->skirt_height) {
            # distribute skirt loops across all extruders
            for my $i (0 .. $#{$self->print->skirt}) {
                # when printing layers > 0 ignore 'min_skirt_length' and 
                # just use the 'skirts' setting; also just use the current extruder
                last if ($layer->id > 0) && ($i >= $Slic3r::Config->skirts);
                $gcode .= $self->gcodegen->set_extruder($self->extruders->[ ($i/@{$self->extruders}) % @{$self->extruders} ])
                    if $layer->id == 0;
                $gcode .= $self->gcodegen->extrude_loop($self->print->skirt->[$i], 'skirt');
            }
        }
        $self->skirt_done->{$layer->print_z} = 1;
        $self->gcodegen->straight_once(1);
    }
    
    # extrude brim
    if (!$self->brim_done) {
        $gcode .= $self->gcodegen->set_extruder($self->extruders->[$Slic3r::Config->support_material_extruder-1]);  # move_z requires extruder
        $gcode .= $self->gcodegen->move_z($layer->print_z);
        $self->gcodegen->set_shift(@{$self->shift});
        $gcode .= $self->gcodegen->extrude_loop($_, 'brim') for @{$self->print->brim};
        $self->brim_done(1);
        $self->gcodegen->straight_once(1);
    }
    
    for my $copy (@$object_copies) {
        $self->gcodegen->new_object(1) if ($self->_last_obj_copy // '') ne "$copy";
        $self->_last_obj_copy("$copy");
        
        $self->gcodegen->set_shift(map $self->shift->[$_] + unscale $copy->[$_], X,Y);
        
        # extrude support material before other things because it might use a lower Z
        # and also because we avoid travelling on other things when printing it
        if ($self->print->has_support_material) {
            $gcode .= $self->gcodegen->move_z($layer->support_material_contact_z)
                if ($layer->support_contact_fills && @{ $layer->support_contact_fills->paths });
            $gcode .= $self->gcodegen->set_extruder($self->extruders->[$Slic3r::Config->support_material_extruder-1]);
            if ($layer->support_contact_fills) {
                $gcode .= $self->gcodegen->extrude_path($_, 'support material contact area') 
                    for $layer->support_contact_fills->chained_path($self->gcodegen->last_pos); 
            }
            
            $gcode .= $self->gcodegen->move_z($layer->print_z);
            if ($layer->support_fills) {
                $gcode .= $self->gcodegen->extrude_path($_, 'support material') 
                    for $layer->support_fills->chained_path($self->gcodegen->last_pos);
            }
        }
        
        # set actual Z - this will force a retraction
        $gcode .= $self->gcodegen->move_z($layer->print_z);
        
        # tweak region ordering to save toolchanges
        my @region_ids = 0 .. ($self->print->regions_count-1);
        if ($self->gcodegen->multiple_extruders) {
            my $last_extruder = $self->gcodegen->extruder;
            my $best_region_id = first { $self->print->regions->[$_]->extruders->{perimeter} eq $last_extruder } @region_ids;
            @region_ids = ($best_region_id, grep $_ != $best_region_id, @region_ids) if $best_region_id;
        }
        
        foreach my $region_id (@region_ids) {
            my $layerm = $layer->regions->[$region_id];
            my $region = $self->print->regions->[$region_id];
            
            my @islands = ();
            if ($Slic3r::Config->avoid_crossing_perimeters) {
                push @islands, { perimeters => [], fills => [] }
                    for 1 .. (@{$layer->slices} || 1);  # make sure we have at least one island hash to avoid failure of the -1 subscript below
                PERIMETER: foreach my $perimeter (@{$layerm->perimeters}) {
                    my $p = $perimeter->unpack;
                    for my $i (0 .. $#{$layer->slices}-1) {
                        if ($layer->slices->[$i]->contour->encloses_point($p->first_point)) {
                            push @{ $islands[$i]{perimeters} }, $p;
                            next PERIMETER;
                        }
                    }
                    push @{ $islands[-1]{perimeters} }, $p; # optimization
                }
                FILL: foreach my $fill (@{$layerm->fills}) {
                    my $f = $fill->unpack;
                    for my $i (0 .. $#{$layer->slices}-1) {
                        if ($layer->slices->[$i]->contour->encloses_point($f->first_point)) {
                            push @{ $islands[$i]{fills} }, $f;
                            next FILL;
                        }
                    }
                    push @{ $islands[-1]{fills} }, $f; # optimization
                }
            } else {
                push @islands, {
                    perimeters  => $layerm->perimeters,
                    fills       => $layerm->fills,
                };
            }
            
            foreach my $island (@islands) {
                # give priority to infill if we were already using its extruder and it wouldn't
                # be good for perimeters
                if ($Slic3r::Config->infill_first
                    || ($self->gcodegen->multiple_extruders && $region->extruders->{infill} eq $self->gcodegen->extruder) && $region->extruders->{infill} ne $region->extruders->{perimeter}) {
                    $gcode .= $self->_extrude_infill($island, $region);
                    $gcode .= $self->_extrude_perimeters($island, $region);
                } else {
                    $gcode .= $self->_extrude_perimeters($island, $region);
                    $gcode .= $self->_extrude_infill($island, $region);
                }
            }
        }
    }
    
    # apply spiral vase post-processing if this layer contains suitable geometry
    $gcode = $self->spiralvase->process_layer($gcode, $layer)
        if defined $self->spiralvase
        && ($layer->id > 0 || $Slic3r::Config->brim_width == 0)
        && ($layer->id >= $Slic3r::Config->skirt_height)
        && ($layer->id >= $Slic3r::Config->bottom_solid_layers);
    
    return $gcode;
}

sub _extrude_perimeters {
    my $self = shift;
    my ($island, $region) = @_;
    
    return "" if !@{ $island->{perimeters} };
    
    my $gcode = "";
    $gcode .= $self->gcodegen->set_extruder($region->extruders->{perimeter});
    $gcode .= $self->gcodegen->extrude($_, 'perimeter') for @{ $island->{perimeters} };
    return $gcode;
}

sub _extrude_infill {
    my $self = shift;
    my ($island, $region) = @_;
    
    return "" if !@{ $island->{fills} };
    
    my $gcode = "";
    $gcode .= $self->gcodegen->set_extruder($region->extruders->{infill});
    for my $fill (@{ $island->{fills} }) {
        if ($fill->isa('Slic3r::ExtrusionPath::Collection')) {
            $gcode .= $self->gcodegen->extrude($_, 'fill') 
                for $fill->chained_path($self->gcodegen->last_pos);
        } else {
            $gcode .= $self->gcodegen->extrude($fill, 'fill') ;
        }
    }
    return $gcode;
}

1;

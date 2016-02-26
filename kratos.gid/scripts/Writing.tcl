namespace eval write {
    variable mat_dict
    variable dir
    variable parts
    variable matun
    variable meshes
}

proc write::Init { } {
    variable mat_dict
    variable dir
    variable parts
    variable meshes
    
    set mat_dict ""
    set dir ""
    set parts ""
    set meshes [dict create]
}

proc write::initWriteData {partes mats} {
    variable parts
    variable matun
    variable meshes
    set parts $partes
    set matun $mats
    
    set meshes [dict create]
    processMaterials
}

# Write Events
proc write::writeEvent { filename } {

    variable dir
    set dir [file dirname $filename]
    
    #set inittime [clock seconds]
    set activeapp [::apps::getActiveApp]
    
    
    #### MDPA Write ####
    set wevent [$activeapp getWriteModelPartEvent]
    
    set filename "[file tail [GiD_Info project ModelName]].mdpa"
    
    catch {CloseFile}
    OpenFile $filename
    
    # Delegate in app
    if { [catch {eval $wevent} fid] } {
        W "Problem Writing MDPA block:\n$fid\nEnd problems"
    }
    catch {CloseFile}
        
    #### Project Parameters Write ####
    set wevent [$activeapp getWriteParametersEvent]
    set filename "ProjectParameters.py"
    
    catch {CloseFile}
    OpenFile $filename
    if { [catch {eval $wevent} fid] } {
        W "Problem Writing Project Parameters block:\n$fid\nEnd problems"
    }
    catch {CloseFile}
        
    #### Custom File Write ####
    set wevent [$activeapp getWriteCustomEvent]
    
    catch {CloseFile}
    if { [catch {eval $wevent} fid] } {
        W "Problem Writing Custom block:\n$fid\nEnd problems"
    }
    catch {CloseFile}
        
    # set endtime [clock seconds]
    # set ttime [expr {$endtime-$inittime}]
    # W "Total time: [Duration $ttime]"
}

proc write::writeModelPartData { } {
    # Write the model part data
     
	WriteString "Begin ModelPartData"
	WriteString "//  VARIABLE_NAME value"
	WriteString "End ModelPartData"
	WriteString ""
}

proc write::writeTables { } {
    # Write the model part data
     
	WriteString "Begin Table"
	WriteString "Table content"
	WriteString "End Tablee"
	WriteString ""
}

proc write::writeMaterials { } {
    variable mat_dict
    
    set exclusionList [list "MID" "ConstitutiveLaw" "Material"]
    # We print all the material data directly from the saved dictionary
    foreach material [dict keys $mat_dict] {
        WriteString "Begin Properties [dict get $mat_dict $material MID]"
        foreach prop [dict keys [dict get $mat_dict $material] ] {
            if {$prop ni $exclusionList} {
                WriteString "    $prop [dict get $mat_dict $material $prop] "
            }
        }
        WriteString "End Properties"
	WriteString ""
    }

}

proc write::writeNodalCoordinates { } {
    # Write the nodal coordinates block
    # Nodes block format
    # Begin Nodes
    # // id          X        Y        Z 
    # End Nodes
    
    WriteString "Begin Nodes"
    write_calc_data coordinates "%5d %14.5f %14.5f %14.5f%.0s\n"
    WriteString "End Nodes"
    WriteString "\n"
}

proc write::processMaterials {  } {
    variable parts
    variable matun
    set doc $gid_groups_conds::doc
    set root [$doc documentElement]
    
    variable mat_dict
    set xp1 "[spdAux::getRoute $parts]/group"
    set xp2 ".//value\[@n='Material']"
    
    set mat_dict ""
    set material_number 0 
    
    foreach gNode [$root selectNodes $xp1] {
        set group [$gNode getAttribute n]
        set valueNode [$gNode selectNodes $xp2]
        set material_name [get_domnode_attribute $valueNode v] 

        if { ![dict exists $mat_dict $group] } {            
            incr material_number
            set mid $material_number
            
            set xp3 [spdAux::getRoute $matun]
            append xp3 [format_xpath {/blockdata[@n="material" and @name=%s]/value} $material_name]
    
            dict set mat_dict $group MID $material_number 
            
            set s1 [$gNode selectNodes ".//value"]
            set s2 [$root selectNodes $xp3]
            set us [join [list $s1 $s2]]
            
            foreach valueNode $us {
                set name [$valueNode getAttribute n]
                set state [get_domnode_attribute $valueNode state]
                if {$state eq "normal" && $name ne "Element"} {
                    # All the introduced values are translated to 'm' and 'kg' with the help of this function
                    set value [gid_groups_conds::convert_value_to_default $valueNode]
                    
                    if {[string is double $value]} {
                        set value [format "%13.5E" $value]
                    }
                    dict set mat_dict $group $name $value
                }
            }
        } 
    }
}

proc write::writeElementConnectivities { } {
    variable parts
    set doc $gid_groups_conds::doc
    set root [$doc documentElement]
    variable mat_dict
    
    set xp1 "[spdAux::getRoute $parts]/group"
    set material_number 0
    foreach gNode [$root selectNodes $xp1] {
        set formats ""
        set group [get_domnode_attribute $gNode n]
        if { [dict exists $mat_dict $group] } {          
            set mid [dict get $mat_dict $group MID]
            if {[$gNode hasAttribute ov]} {set ov [get_domnode_attribute $gNode ov] } {set ov [get_domnode_attribute [$gNode parent] ov] }
            #W $ov
            lassign [getEtype $ov] etype nnodes
            #W "$group $ov -> $etype $nnodes"
            if {$nnodes ne ""} {
                set formats [GetFormatDict $group $mid $nnodes]
                
                if {$etype ne "none"} {
                    set kelemtype [get_domnode_attribute [$gNode selectNodes ".//value\[@n='Element']"] v]
                    set elem [::Model::getElement $kelemtype]
                    #W $kelemtype
                    set top [$elem getTopologyFeature $etype $nnodes]
                    if {$top eq ""} {W "Element $kelemtype not available for $ov entities on group $group"; continue}
                    set kratosElemName [$top getKratosName]
                    #W "Writing $formats"
                    WriteString "Begin Elements $kratosElemName// GUI group identifier: $group" 
                    write_calc_data connectivities $formats
                    WriteString "End Elements"
                    WriteString ""     
                } else {
                    W "Error on $group -  no known element type"
                    # error [= "Only Triangle elements are allowed in this version of the problemtype"]
                } 
            }    
        }
    } 
}
proc write::getMeshId {group} {
    variable meshes
    if {[dict exists $meshes $group]} {
        return [dict get $meshes $group]
    } {
        return 0
    }
    
}

proc write::writeGroupMesh { group {what "Elements"} {iniend ""} } {
    variable meshes
    #W "Print Mesh - group $group $what"
    # Ojo, Si se comparte el mismo grupo en Parts y en Loads/DoF
    if {![dict exists $meshes $group]} {
        set mid [expr [llength [dict keys $meshes]] +1]
        dict set meshes $group $mid
        set gdict [dict create]
        set f "%10i\n"
        set f [subst $f]
        dict set gdict $group $f
        #W "Group Mesh $group"
        WriteString "Begin Mesh $mid // Group $group"
        WriteString "Begin MeshNodes"
        write_calc_data nodes -sorted $gdict
        WriteString "End MeshNodes"
        WriteString "Begin MeshElements"
        if {$what eq "Elements"} {
            write_calc_data elements -sorted $gdict
        }
        WriteString "End MeshElements"
        WriteString "Begin MeshConditions"
        if {$what eq "Conditions"} {
            #write_calc_data elements -sorted $gdict
            if {$iniend ne ""} {
                lassign $iniend ini end
                for {set i $ini} {$i<=$end} {incr i} {
                    WriteString $i
                }
            }
        }
        WriteString "End MeshConditions"
        WriteString "End Mesh"
    }
}

proc write::writeNodalData { uniqueName } {
    set doc $gid_groups_conds::doc
    set root [$doc documentElement]
    
    # Get all childs of uniquename Groups
    set xp1 "[apps::getRoute $uniqueName]/group"
    foreach group [$root selectNodes $xp1] {
        writeNodalDataGroupNode $group
    }
}

proc write::writeNodalDataGroupNode { group } {
    # W "group $group [$group @n]"
    
    lassign {1 1 1 0 0 0 X Y Z} fix_x fix_y fix_z xval yval zval wx wy wz
    foreach prop [$group childNodes] {
        set name [get_domnode_attribute $prop n]
       
        switch $name {
            "FixX" {
                set fix_x [get_domnode_attribute $prop v]
            }
            "FixY" {
                set fix_y [get_domnode_attribute $prop v]
            }
            "FixZ" {
                set fix_z [get_domnode_attribute $prop v]
            }
            "ValX" {
                set xval [gid_groups_conds::convert_value_to_default $prop] 
                set wx [$prop @wn]
                if {$wx eq ""} {set wx [$prop @n]}
            }
            "ValY" {
                set yval [gid_groups_conds::convert_value_to_default $prop] 
                set wy [$prop @wn]
            }
            "ValZ" {
                set zval [gid_groups_conds::convert_value_to_default $prop] 
                set wz [$prop @wn]
            }
        }
    }
    
    # Create the dictionary formats
    set gpropdx [dict create]
    set gpropdy [dict create]
    set gpropdz [dict create]
    set groupname [$group @n]
    
    # For X
    set f "%10i [format "%4i" $fix_x] [format "%10.5f" $xval]\n"
    set f [subst $f]
    dict set gpropdx $groupname $f
    # For Y
    set f "%10i [format "%4i" $fix_y] [format "%10.5f" $yval]\n"
    set f [subst $f]
    dict set gpropdy $groupname $f
    # For Z
    set f "%10i [format "%4i" $fix_z] [format "%10.5f" $zval]\n"
    set f [subst $f]
    dict set gpropdz $groupname $f
    
    if {[write_calc_data nodes -count $gpropdx]>0} {
        # X Component
        WriteString "Begin NodalData $wx"
        write_calc_data nodes -sorted $gpropdx
        WriteString "End NodalData"
        WriteString ""        
    
        # Y Component
        WriteString "Begin NodalData $wy"
        write_calc_data nodes -sorted $gpropdy
        WriteString "End NodalData"
        WriteString ""        
    
        # Z Component
        WriteString "Begin NodalData $wz"
        write_calc_data nodes -sorted $gpropdz
        WriteString "End NodalData"
        WriteString ""        
    }
}

proc write::GetTopologyInfo { } {
    return [list "Point" 1]
}

proc write::GetFormatDict { groupid n num} {
    set f "%10d [format "%10d" $n] [string repeat "%10d " $num]\n"
    #set f [subst $f]
    return [dict create $groupid $f]
}


proc write::getEtype1 {group} {
    dict set formats $group "%d"
    set etype "none"
    W "Data from $group"
    W "Nodes [write_calc_data nodes -count $formats]"
    W "Faces [write_calc_data has_elements -elements_faces "faces" $formats]"
    W "Elements [write_calc_data elements -elemtype "Tetrahedra" -count $formats]"
    set f {%5d }
    set f [subst $f]
    dict set fo $group $f
    W "a ver [write_calc_data elements -return $fo]"
    
    if {[write_calc_data has_elements -elemtype "Triangle" -elements_faces "all" $formats]} {
        set etype "Triangle"
    } elseif {[write_calc_data has_elements -elemtype "Quadrilateral" $formats]} {
        set etype "Quadrilateral"
    } elseif {[write_calc_data has_elements -elemtype "Tetrahedra" $formats]} {
        set etype "Tetrahedra"
    } elseif {[write_calc_data has_elements -elemtype "Hexahedra" $formats]} {
        set etype "Hexahedra"
    } elseif {[write_calc_data has_elements -elemtype "Sphere" $formats]} {
        set etype "Sphere"
    } elseif {[write_calc_data has_elements -elemtype "Point" $formats]} {
        set etype "Point"
    }
    W $etype
    #return $etype
}

proc write::getEtype {ov} {
    set isquadratic [isquadratic]
    set ret [list "" ""]
    
    if {$ov eq "point"} {
        set ret [list "Point" 1]
    }
    
    if {$ov eq "line"} {
        switch $isquadratic {
            0 { set ret [list "Linear" 2] }
            default { set ret [list "Linear" 2] }                                         
        } 
    }
    
    if {$ov eq "surface"} {
        foreach ielem [lrange [GiD_Info Mesh] 1 end] {
            switch $ielem {
                Triangle {          
                    switch $isquadratic {
                        0 { set ret [list "Triangle" 3]  }
                        default { set ret [list "Triangle" 6]  }
                    }
                }
                Tetrahedra {          
                    switch $isquadratic {
                        0 { set ret [list "Triangle" 3]  }
                        default { set ret [list "Triangle" 6]  }
                    }
                }           
                Quadrilateral {          
                    switch $isquadratic {
                        0 { set ret [list "Quadrilateral" 4]  }                
                        1 { set ret [list "Quadrilateral" 8]  }                
                        2 { set ret [list "Quadrilateral" 9]  }                
                    }
                }
            }
        }
    }
    
    if {$ov eq "volume"} {
        foreach ielem [lrange [GiD_Info Mesh] 1 end] {
            switch $ielem {
                Tetrahedra {          
                    switch $isquadratic {
                        0 { set ret [list "Tetrahedra" 4]  }               
                        1 { set ret [list "Tetrahedra" 10] }                
                        2 { set ret [list "Tetrahedra" 10] }  
                    }
                }           
                Hexahedra {          
                    switch $isquadratic {
                        0 { set ret [list "Hexahedra" 8]  }                
                        1 { set ret [list "Hexahedra" 20]  }                
                        2 { set ret [list "Hexahedra" 27]  }                
                    }
                }
            }
        }
    }
    
    return $ret
}
proc write::isquadratic {} {     
    
    set err [catch { GiD_Set Model(QuadraticType) } isquadratic]
    if { $err } {
        set isquadratic [lindex [GiD_Info Project] 5]
    }
    return $isquadratic
}


proc write::WriteProcess {procid params} {
	W "$procid $params"
}

# Auxiliar
proc write::Duration { int_time } {
    # W "entro con $int_time"
    set timeList [list]
    foreach div {86400 3600 60 1} mod {0 24 60 60} name {day hr min sec} {
        set n [expr {$int_time / $div}]
        if {$mod > 0} {set n [expr {$n % $mod}]}
        if {$n > 1} {
            lappend timeList "$n ${name}s"
        } elseif {$n == 1} {
            lappend timeList "$n $name"
        }
    }
    return [join $timeList]
}
 
proc write::getValue { name { it "" } } {
    set doc $gid_groups_conds::doc
    set root [$doc documentElement]
    
    set xp [apps::getRoute $name]
    set node [$root selectNodes $xp]
    if {$it ne ""} {set node [$node find n $it]}
    
    if {[get_domnode_attribute $node v] eq ""} {
        catch {get_domnode_attribute $node values}
    }
    set v [get_domnode_attribute $node v]
    return $v
 }

proc write::getStringBinaryValue { name { it "" } } {
    set v [getValue $name $it]
    set goodList [list "Yes" "1" "yes" "ok" "YES" "Ok" "True" "TRUE" "true"]
    if {$v in $goodList} {return "True" } {return "False"}
}
 
proc write::OpenFile { fn } {
    variable dir
    set filename [file join $dir $fn]
    catch {CloseFile}
    write_calc_data init $filename
}

proc write::CloseFile { } {
    catch {write_calc_data end}
}

proc write::WriteString {str} {
    #W [format "%s" $str]
    write_calc_data puts [format "%s" $str]
}

proc write::getMatDict {} {
    variable mat_dict
    return $mat_dict
}

proc write::CopyFileIntoModel { filepath } {
    variable dir
    
    set activeapp [::apps::getActiveApp]
    set inidir [apps::getMyDir [$activeapp getName]]
    set totalpath [file join $inidir $filepath]
    file copy -force $totalpath $dir
}

write::Init
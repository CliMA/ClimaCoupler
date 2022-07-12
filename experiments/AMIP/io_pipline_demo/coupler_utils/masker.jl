function LandSeaMask(FT, mask_data, varname, h_space; outfile = "land_sea_cgll.nc", threshold = 0.7)
    LSMASK_info = bcfile_info_init(mask_data, "LSMASK", boundary_space, segment_idx0 = [Int(1)], scaling_function = clean_mask) # TODO: dispatch
    update_midmonth_data!(date0, LSMASK_info)
end

"""
clean_mask(FT, mask)
- convert to integer values after interpolation (but keep type as floats for easier calculation (TODO))
"""
clean_mask(mask) = clean_mask.(mask, FT(0.5))
clean_mask(mask, threshold) = mask > FT(threshold) ? FT(1) : FT(0)

combine_surface(FT, mask, sfc_1, sfc_2, sfc_3, value1 = -0.5, value2 = 0.5) =
    (mask < FT(value1) ? sfc_3 : FT(0)) +
    ((mask >= FT(value1) && (mask <= FT(value2))) ? sfc_2 : FT(0)) +
    (mask > FT(value2) ? sfc_1 : FT(0))

"""
apply_mask(mask, condition, field, value = 0.5) 

"""
apply_mask(mask, condition, field, value) = condition(mask, value) ? field : 0.0

"""
    time_slice_ncfile(sic_data, time_idx = 1)
- slices a dataset at time index `time_idx` and saves it under `sic_data_slice`. Used for more efficient regridding of mask, SST and SIC files. 
"""
function time_slice_ncfile(sic_data, time_idx = 1)
    sic_data_slice = sic_data[1:(end - 3)] * "_one_time.nc"
    isfile(sic_data_slice) ? run(`rm $sic_data_slice`) : nothing
    NCDataset(sic_data) do ds
        write(sic_data_slice, ds, idimensions = Dict("time" => time_idx:time_idx))
    end
    return sic_data_slice
end

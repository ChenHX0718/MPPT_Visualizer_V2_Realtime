function exportCSV(data, path)
%EXPORTCSV Preserve all received fields, plus this session's derived values.
records=data.rawRecords; names={};
for k=1:numel(records), names=union(names,fieldnames(records{k}),'stable'); end
names=reshape(names,1,[]); rawCount=numel(names);
derived={'Time_s','SolarPower_W','Energy_Wh','Capacity_mAh'};
for k=1:numel(derived)
    name=derived{k};
    while any(strcmp(names,name)), name=['Computed_',name]; end %#ok<AGROW>
    names{end+1}=name; %#ok<AGROW>
end
cells=cell(numel(records),numel(names));
for r=1:numel(records)
    for c=1:numel(names)
        name=names{c};
        if c>rawCount
            cells{r,c}=data.(derived{c-rawCount})(r);
        elseif isfield(records{r},name)
            value=records{r}.(name);
            if (isnumeric(value) || islogical(value)) && isscalar(value)
                cells{r,c}=value;
            elseif ischar(value) || (isstring(value) && isscalar(value))
                cells{r,c}=char(value);
            else
                cells{r,c}=jsonencode(value);
            end
        else
            cells{r,c}='';
        end
    end
end
writecell([names;cells],path,'Encoding','UTF-8');
end

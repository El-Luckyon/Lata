--!strict
--!optimize 2
--!native

export type ContainerId = number

export type Meta = {
    CreatedTime : number,
    LastSaveTime : number,
    ActiveSessionId : string,
    LastSavedSessionId : string,
    Version : number,
}

export type Container = {
    Key : string | number,
    Data : {any},
    Meta : Meta
}

export type DataType = {
    Name : string,
    DefaultData : {any},
    Containers : {Container},
    KeyToContainer : {[string | number] : number},
    DataKeyToIndex : {[string] : number},
    Data : (DataType : DataType, Key : string | number) -> ContainerId,
    Find : (DataType : DataType, ContainerId : ContainerId, DataKey : string?) -> nil | {any} | any,
}

local DataTypes : {DataType} = {}
local NameToDataType : {[string] : number} = {}

local function CreateNewMeta() : Meta
    local Meta : Meta = {
        CreatedTime = os.time(),
        LastSaveTime = -1,
        ActiveSessionId = "null",
        LastSavedSessionId = "null",
        Version = 0,
    }
    return Meta
end

local function CreateNewContainer(DataType : DataType, Key : string | number) : ContainerId
    local Meta = CreateNewMeta()
    local DefaultData = DataType.DefaultData
    local Container : Container = {
        Key = Key,
        Data = table.create(#DefaultData, DefaultData),
        Meta = Meta,
    }
    table.insert(DataType.Containers, Container)
    local ContainerId : ContainerId = #DataType.Containers
    DataType.KeyToContainer[Key] = ContainerId
    return ContainerId
end

local function FindSpecificData(DataType : DataType, ContainerId : ContainerId, DataKey : string?) : nil | {any} | any
    local Container = DataType.Containers[ContainerId]
    assert(Container, "No container found for the given id, id="..tostring(ContainerId))
    if not DataKey then
        return Container.Data
    end
    local Index = DataType.DataKeyToIndex[DataKey]
    return Container.Data[Index]
end

local function BuildTemplate(Template : {[string] : any}) : ({any}, {[string] : number})
    local DefaultData : {any} = {}
    local DataKeyToIndex : {[string] : number} = {}
    local Index = 1
    for DataKey, Data in Template do
        DefaultData[Index] = Data
        DataKeyToIndex[DataKey] = Index
        Index += 1
    end
    return DefaultData, DataKeyToIndex
end

local function CreateNewDataType(Name : string, Template : {[string] : any}) : DataType
    local Index = NameToDataType[Name]
    if Index then
        return DataTypes[Index]
    end
    local DefaultData, DataKeyToIndex = BuildTemplate(Template)
    local DataType : DataType = {
        Name = Name,
        Containers = {},
        KeyToContainer = {},
        DefaultData = DefaultData,
        DataKeyToIndex = DataKeyToIndex,
        Data = CreateNewContainer,
        Find = FindSpecificData,
    }
    table.insert(DataTypes, DataType)
    local Id = #DataTypes
    NameToDataType[Name] = Id
    return DataType
end

local Lata = {}

Lata.New = CreateNewDataType

return Lata
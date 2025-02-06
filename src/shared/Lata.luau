--!strict
--!optimize 2
--!native

export type ContainerId = string

export type Meta = {
    CreatedTime : number,
    LastSaveTime : number,
    ActiveSessionId : string,
    LastSavedSessionId : string,
    Version : number,
}

export type Container = {
    Key : string,
    Data : {any},
    Meta : Meta
}

export type DataType = {
    Name : string,
    DefaultData : {any},
    Containers : {[ContainerId] : Container},
    DataKeyToIndex : {[string] : number},
    Data : (DataType : DataType, Key : ContainerId) -> ContainerId,
    Find : (DataType : DataType, ContainerId : ContainerId, DataKey : string?) -> nil | {any} | any,
    Set : (DataType : DataType, ContainerId : ContainerId, Value : any, DataKey : string?) -> (),
    Del : (DataType : DataType, ContainerId : ContainerId) -> (),
}

local MAIN_DATA_STORE_ID = "MAIN"
local BACKUP_DATA_STORE_ID = "BACKUP"

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MainDataStore: DataStore = DataStoreService:GetDataStore(MAIN_DATA_STORE_ID)
local BackupDataStore: DataStore = DataStoreService:GetDataStore(BACKUP_DATA_STORE_ID)

local DataTypes : {DataType} = {}
local NameToDataType : {[string] : number} = {}


local function EncodeContainer(Container : Container) : string
    return HttpService:JSONEncode({Container.Data, Container.Meta})
end

local function DecodeContainer(SaveString : string): ...any
    return table.unpack(HttpService:JSONDecode(SaveString))
end

local function Save(Container : Container, DataStore : DataStore, ShouldCloseSession : boolean?) : number
    local Key = Container.Key
    local CurrentMeta = Container.Meta

    local Status = 0

    local Success: boolean, Returns: any = pcall(function()
        return DataStore:UpdateAsync(Key, function(PreviousCopy : string)
            if not PreviousCopy then
                Status = -1
                return "__corrupted__"
            end

            local PreviousData : {any}, PreviousMeta : Meta = DecodeContainer(PreviousCopy)

            if PreviousMeta.ActiveSessionId ~= CurrentMeta.ActiveSessionId then
                Status = -2
				return PreviousCopy
            end

            if PreviousMeta.Version > CurrentMeta.Version then
                Status = -3
				return PreviousCopy
            end

            if ShouldCloseSession then
                Container.Meta.ActiveSessionId = "null"
            end

            CurrentMeta.LastSavedSessionId = CurrentMeta.ActiveSessionId
            CurrentMeta.Version += 1
            CurrentMeta.LastSaveTime = time()
            Status = 1
            return EncodeContainer(Container)
        end)
    end)

    if not Success then
        warn(Returns)
    end

    return Status
end

local function Load(Container : Container, DataStore : DataStore) : number
    local Key = Container.Key
    local CurrentMeta = Container.Meta

    local Status = 0

    local Success: boolean, Returns: any = pcall(function()
        return DataStore:UpdateAsync(Key, function(PreviousCopy : string)
            if not PreviousCopy then
                Status = 1
                return EncodeContainer(Container)
            end

            if PreviousCopy == "__corrupted__" then
                --// Perform Some Damage Control
                Status = -1
				return PreviousCopy
            end

            local PreviousData, PreviousMeta = DecodeContainer(PreviousCopy)

            if PreviousMeta.ActiveSessionId ~= "null" then
                Status = -2
				return PreviousCopy
            end

            if PreviousMeta.LastSavedSessionId == CurrentMeta.ActiveSessionId then
                Status = -3
				return PreviousCopy
            end

            PreviousMeta.ActiveSessionId = CurrentMeta.ActiveSessionId
            Container.Meta = PreviousMeta
            Container.Data = PreviousData
            
            Status = 2
            return EncodeContainer(Container)
        end)
    end)

    if not Success then
        warn(Returns)
    end

    return Status
end

local function CreateNewMeta() : Meta
    local Meta : Meta = {
        CreatedTime = os.time(),
        LastSaveTime = -1,
        ActiveSessionId = HttpService:GenerateGUID(false),
        LastSavedSessionId = "null",
        Version = 0,
    }
    return Meta
end

local function CreateNewContainer(DataType : DataType, Key : ContainerId) : ContainerId
    local Meta = CreateNewMeta()
    local DefaultData = DataType.DefaultData
    local ContainerId : ContainerId = tostring(Key)
    local Container : Container = {
        Key = DataType.Name..'/'..tostring(Key),
        Data = table.clone(DefaultData),
        Meta = Meta,
    }
    DataType.Containers[ContainerId] = Container
    local Status = Load(Container, MainDataStore)
    print(Status)
    return ContainerId
end

local function DestroyContainer(DataType : DataType, ContainerId : ContainerId) : ()
    local Container = DataType.Containers[ContainerId]
    local Meta = Container.Meta

    local Status = Save(Container, MainDataStore, true)
    print(Status)
    if Status == 1 then
        DataType.Containers[ContainerId] = nil
    end
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

local function SetSpecificData(DataType : DataType , ContainerId : ContainerId, Value : any, DataKey : string?): ()
    local Container = DataType.Containers[ContainerId]
    assert(Container, "No container found for the given id, id="..tostring(ContainerId))
    if not DataKey then
        print("[LATA][INFO] Complete data overiddes are discouraged, key=", DataKey, "DataType=", DataType.Name)
        Container.Data = Value
    else
        local Index = DataType.DataKeyToIndex[DataKey]
        Container.Data[Index] = Value
    end
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
        DefaultData = DefaultData,
        DataKeyToIndex = DataKeyToIndex,
        Data = CreateNewContainer,
        Find = FindSpecificData,
        Del = DestroyContainer,
        Set = SetSpecificData,
    }
    table.insert(DataTypes, DataType)
    local Id = #DataTypes
    NameToDataType[Name] = Id
    return DataType
end

local Lata = {}

Lata.New = CreateNewDataType

return Lata
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
--[[
TODO:
*Add adding/removing keys from datatypes after first creation
*Add configs
*Add error callbacks implmentation
*Make it so default error callbacks can be overriden by the user using configs
*Implement Auto Saving
*Implement Proper BindToClose
*Implement Data Intergrity Checks
*Implement Auto Backups
]]

--[[
    Lata is a simple to use data store module.
    Its based on the principle of fragmented data.
    The Datatype object acts in a similar fashion to a datastore from :GetDataStore()
    the containers are ur unique data in the datatype
    everytime u create a container the container gets filled with the default data and then it trys to fetch from the datastore if the fetch is success the data is updated
    whenever u fetch data it creates a session for that data and the session is updated in the datastore
    whenever u destroy a container the data is saved and the session is released.

    when ur using Lata its highly recommened that you create seperate datatypes for each type of player data instead of one datatype called player data
    ie: inventory, pets, eco,
    yes this does increase the api calls but its add the benefit that one error cannot lead to total loss of data
    its also very unlikely u will have more than 3-4 data types to saves in a game
    its also recommended that you keep the datatypes less than 10 per player since this would stop us from exceeding the 10 calls/min per player limit

    in Lata you have the same key usually the player's userid to store multiple data like inventory, pets, and eco with the same key.
]]--


local MAIN_DATA_STORE_ID = "MAIN"
local BACKUP_DATA_STORE_ID = "BACKUP"

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MainDataStore: DataStore = DataStoreService:GetDataStore(MAIN_DATA_STORE_ID)
local BackupDataStore: DataStore = DataStoreService:GetDataStore(BACKUP_DATA_STORE_ID)

local DataTypes : {[string] : DataType} = {}

--// TODO Will encode data efficiently into a single string
local function EncodeContainer(Container : Container) : string
    return HttpService:JSONEncode({Container.Data, Container.Meta})
end

--// TODO will decode data from the string into a lua table containing data and metadata
local function DecodeContainer(SaveString : string): ...any
    return table.unpack(HttpService:JSONDecode(SaveString))
end

--[[
Status Codes:
-1 No previous data
-2 Session doesn't match
-3 Newer version exsists
1 success

Main save method takes a container and datastore to allow for backup datastores and a parameter to wether close the session
checks for the previous copy in the datastore must exsists since the default data is saved the first time the data is loaded if it doesn't exsist sets the current data
to corrupted flag and returns status code -1.
then checks if the session id the datastore matches the session id in the server (the sessionid is set in the cloud when data is loaded)
if they don't match it doesn't change anything and returns status code -2
then checks for version if the current version is lower than the version in the server the save request is dropped and returns status code -3

if all the checks pass
we increment the current version
we set the lastsave time
we also set the last saved session id
and finnaly update the data after encoding it into a string
]]
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

--[[
Status Codes:
1 success, first load
2 success, not first load
-1 corrupted data
-2 another active session
-3 session is already open

main load methods get the previous copy
checks if the previous data has the corrupted flag if it does then some error handling callback will be fired. -1
checks if the previous session id is null which will be null if the previous session was deleted using Datatype:Del(Container) if not null returns status code -2
checks if the last saved session id matches the current session if it matches that means this session was already loaded once and the request is dropped
and returns status code -3

if all checks passed then
active session id is updated in the datastore
and the containers data is updated
]]
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
                --//TODO Perform Some Damage Control
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

--[[
Creates a meta a meta is just metadata of the container like the first time it was created and bunch of other stuff used by Lata to do its thing.
the user generally doesn't interact with meta data thats why there is no public method to access it
]]
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

--[[
TODO: Implement a way to remove data and add new data to the container after its been created once.

Creates a new container a container holds metadata and its data
data is stored in an array and datatype has a table that points a key to a certain index of this array
the container's key is the combination of the datatype's name and ContainerId
the container id is the unique id given by the user ie: player.userid or similar
the containers data is set to default data the moment its created.
but immediatly after creation the data is loaded from the datastore.

if the container with the same key already exsists then returns the cached container.

containers will not be uncached until the DataType:Del(Container) method is called
]]
local function CreateNewContainer(DataType : DataType, ContainerId : ContainerId) : ContainerId
    local _Container = DataType[ContainerId]
    if _Container then
        return _Container
    end
    local Meta = CreateNewMeta()
    local DefaultData = DataType.DefaultData
    local Container : Container = {
        Key = DataType.Name..'/'..tostring(ContainerId),
        Data = table.clone(DefaultData),
        Meta = Meta,
    }
    DataType.Containers[ContainerId] = Container
    local Status = Load(Container, MainDataStore)
    return ContainerId
end

--[[
Simple method to get rid of containers from the server's cache
trys to save the container if success removed from memory else error callback should be invoked
]]
local function DestroyContainer(DataType : DataType, ContainerId : ContainerId) : ()
    local Container = DataType.Containers[ContainerId]
    local Meta = Container.Meta

    local Status = Save(Container, MainDataStore, true)
    if Status == 1 then
        DataType.Containers[ContainerId] = nil
    end
end

--[[
a method to find the a specific data like "Sword" or "Bow" from a datatype like inventory for an container.
first checks for a valid container then
returns the entire container data is no key is passed else returns the corresponding value.
if key is not found in datatype returns nil
]]
local function FindSpecificData(DataType : DataType, ContainerId : ContainerId, DataKey : string?): any
    local Container = DataType.Containers[ContainerId]
    assert(Container, "No container found for the given id, id="..tostring(ContainerId))
    if not DataKey then
        return Container.Data
    end
    local Index = DataType.DataKeyToIndex[DataKey]
    return Container.Data[Index]
end

--[[
a method to set a specific data from a datatype to a container.
works similar to the FindSecificData method.
]]
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

--[[
this methods build the default data and keytoindex table from a templated provided by the user.
it works by looping thru the template and appending the index to default data and mapping the index to the key.
]]
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

--[[
the main method of Lata
used to create a new DataType
a DataType is collection of containers containing the same type of data within it
a datatypes stores all its containers
and map that maps the keys given by the user to specific index in the containers data array
its also the main object the user interacts with
the method either creates a datatype if the name is passed in the first time or returns the cached datatype for that name
if called after that
]]
local function CreateNewDataType(Name : string, Template : {[string] : any}) : DataType
    local _DataType = DataTypes[Name]
    if _DataType then
        return _DataType
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
    DataTypes[Name] = DataType
    return DataType
end

local Lata = {}

Lata.New = CreateNewDataType

return Lata
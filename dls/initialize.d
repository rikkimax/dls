module dls.initialize;

import rt.dbg;
import cjson = cjson;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.ctype;

import dls.main;




void lsp_initialize(int id) {
    auto result = cjson.cJSON_CreateObject();

    auto capabilities = cjson.cJSON_AddObjectToObject(result, "capabilities");
    cjson.cJSON_AddNumberToObject(capabilities, "textDocumentSync", 1);
    cjson.cJSON_AddBoolToObject(capabilities, "hoverProvider", 0);
    cjson.cJSON_AddBoolToObject(capabilities, "definitionProvider", 1);
    cjson.cJSON_AddBoolToObject(capabilities, "documentSymbolProvider", 1);

    auto completion = cjson.cJSON_AddObjectToObject(capabilities, "completionProvider");
    cjson.cJSON_AddBoolToObject(completion, "resolveProvider", 0);

    const(char)*[6] tc = [ ".","=","/","*","+","-"];
    auto triggerCharacters = cjson.cJSON_CreateStringArray(tc.ptr, tc.length);
    cjson.cJSON_AddItemToObject(completion, "triggerCharacters", triggerCharacters);

    auto completionItem = cjson.cJSON_AddObjectToObject(completion, "completionItem");
    cjson.cJSON_AddBoolToObject(completionItem, "labelDetailsSupport", 1);

    auto serverInfo = cjson.cJSON_AddObjectToObject(result, "serverInfo");
    cjson.cJSON_AddStringToObject(serverInfo, "name", "dls");
    cjson.cJSON_AddStringToObject(serverInfo, "version", "0.0.1");

    lsp_send_response(id, result);
}

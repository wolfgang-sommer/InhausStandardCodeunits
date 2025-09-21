codeunit 50152 INHWhseActRegisterYesNo
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // A08°          RBI  29.07.08  Meldung deaktiviert

    TableNo = "Warehouse Activity Line";

    trigger OnRun()
    begin
        WhseActivLine.Copy(Rec);
        Code;
        Rec.Copy(WhseActivLine);
    end;

    var
        Text001: Label 'Do you want to register the %1 Document?';
        WhseActivLine: Record "Warehouse Activity Line";
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
        WMSMgt: Codeunit "WMS Management";
        Text002: Label 'The document %1 is not supported.';

    local procedure "Code"()
    begin
        OnBeforeCode(WhseActivLine);

        with WhseActivLine do begin
            if ("Activity Type" = "Activity Type"::"Invt. Movement") and
               not ("Source Document" in ["Source Document"::" ",
                                          "Source Document"::"Prod. Consumption",
                                          "Source Document"::"Assembly Consumption"])
            then
                Error(Text002, "Source Document");

            WMSMgt.CheckBalanceQtyToHandle(WhseActivLine);

            //START A08° ---------------------------------
            //  IF NOT CONFIRM(Text001,FALSE,"Activity Type") THEN
            //    EXIT;
            //STOP  A08° ---------------------------------

            WhseActivityRegister.Run(WhseActivLine);
            Clear(WhseActivityRegister);
        end;

        OnAfterCode(WhseActivLine);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCode(var WarehouseActivityLine: Record "Warehouse Activity Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCode(var WarehouseActivityLine: Record "Warehouse Activity Line")
    begin
    end;
}


codeunit 50142 INHShipmentHeaderEdit
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // A17°          JLE  04.06.08  Änderung von "Fakturafreigabe" zulassen
    // A17°.1        SSC  14.09.16  Fakturafreigabe ändern mit Recht versehen

    Permissions = TableData "Sales Shipment Header" = rm;
    TableNo = "Sales Shipment Header";

    trigger OnRun()
    var
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_re_Benutzerberechtigung: Record Benutzerberechtigungen;
    begin
        SalesShptHeader := Rec;
        SalesShptHeader.LockTable;
        SalesShptHeader.Find;
        SalesShptHeader."Shipping Agent Code" := "Shipping Agent Code";
        SalesShptHeader."Shipping Agent Service Code" := "Shipping Agent Service Code";
        SalesShptHeader."Package Tracking No." := "Package Tracking No.";
        OnBeforeSalesShptHeaderModify(SalesShptHeader, Rec);
        SalesShptHeader.TestField("No.", "No.");

        //START A17° ---------------------------------
        lo_re_Benutzerberechtigung.Get(UserId);
        lo_re_Benutzerberechtigung.TestField("VK-Fakturafreigabe", true);   //A17°.1
        if (Fakturafreigabe = Fakturafreigabe::fakturiert) and (not lo_re_Benutzerberechtigung."VK-Fakturafreigabe") then
            Error(TextErrorFakturaKZChange);
        SalesShptHeader.Fakturafreigabe := Fakturafreigabe;
        SalesShptHeader."Ladelistenr." := "Ladelistenr.";
        //STOP  A17° ---------------------------------

        SalesShptHeader.Modify;
        Rec := SalesShptHeader;
    end;

    var
        SalesShptHeader: Record "Sales Shipment Header";
        "+++TE_INHAUS+++": ;
        TextErrorFakturaKZChange: Label 'Fakturakennzeichen darf manuell nicht auf "fakturiert" gesezt werden !';

    [IntegrationEvent(false, false)]
    local procedure OnBeforeSalesShptHeaderModify(var SalesShptHeader: Record "Sales Shipment Header"; FromSalesShptHeader: Record "Sales Shipment Header")
    begin
    end;
}


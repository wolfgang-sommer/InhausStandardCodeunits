codeunit 50174 INHCustCheckCrLimit
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // B43°.1        SSC  03.07.12  fnk_CreditLimitExceeded
    // B43°.3        SSC  11.11.15  Neue fnk_GetOutstOrd4CrLimitFilter
    //               SSC  04.10.24  Nächsten Arbeitstag korrekt berücksichtigen, nicht nur nächsten Tag

    Permissions = TableData "My Notifications" = rimd;

    trigger OnRun()
    begin
    end;

    var
        InstructionMgt: Codeunit "Instruction Mgt.";
        NotificationLifecycleMgt: Codeunit "Notification Lifecycle Mgt.";
        CustCheckCreditLimit: Page "Check Credit Limit";
        InstructionTypeTxt: Label 'Check Cr. Limit';
        GetDetailsTxt: Label 'Show details';
        CreditLimitNotificationMsg: Label 'The customer''s credit limit has been exceeded.';
        CreditLimitNotificationDescriptionTxt: Label 'Show warning when a sales document will exceed the customer''s credit limit.';
        OverdueBalanceNotificationMsg: Label 'This customer has an overdue balance.';
        OverdueBalanceNotificationDescriptionTxt: Label 'Show warning when a sales document is for a customer with an overdue balance.';
        "+++TE_INHAUS+++": ;
        TextCreditLimitExceeded: Label 'Das Kreditlimit dieses Debitors(%1) wurde überschritten. Bitte melden Sie sich in der Buchhaltung! Auftrag kann nicht verwendet werden.';

    procedure GenJnlLineCheck(GenJnlLine: Record "Gen. Journal Line")
    var
        SalesHeader: Record "Sales Header";
        AdditionalContextId: Guid;
    begin
        if not GuiAllowed then
            exit;

        if not SalesHeader.Get(GenJnlLine."Document Type", GenJnlLine."Document No.") then
            SalesHeader.Init;
        OnNewCheckRemoveCustomerNotifications(SalesHeader.RecordId, true);

        if CustCheckCreditLimit.GenJnlLineShowWarningAndGetCause(GenJnlLine, AdditionalContextId) then
            CreateAndSendNotification(SalesHeader.RecordId, AdditionalContextId, '');
    end;

    procedure SalesHeaderCheck(var SalesHeader: Record "Sales Header") CreditLimitExceeded: Boolean
    var
        AdditionalContextId: Guid;
    begin
        if not GuiAllowed then
            exit;

        OnNewCheckRemoveCustomerNotifications(SalesHeader.RecordId, true);

        if not CustCheckCreditLimit.SalesHeaderShowWarningAndGetCause(SalesHeader, AdditionalContextId) then
            SalesHeader.OnCustomerCreditLimitNotExceeded
        else
            if InstructionMgt.IsEnabled(GetInstructionType(Format(SalesHeader."Document Type"), SalesHeader."No.")) then begin
                CreditLimitExceeded := true;

                CreateAndSendNotification(SalesHeader.RecordId, AdditionalContextId, '');
                SalesHeader.OnCustomerCreditLimitExceeded;
            end;
    end;

    procedure SalesLineCheck(SalesLine: Record "Sales Line")
    var
        SalesHeader: Record "Sales Header";
        AdditionalContextId: Guid;
    begin
        if not GuiAllowed then
            exit;

        if not SalesHeader.Get(SalesLine."Document Type", SalesLine."Document No.") then
            SalesHeader.Init;
        OnNewCheckRemoveCustomerNotifications(SalesHeader.RecordId, false);

        if not CustCheckCreditLimit.SalesLineShowWarningAndGetCause(SalesLine, AdditionalContextId) then
            SalesHeader.OnCustomerCreditLimitNotExceeded
        else
            if InstructionMgt.IsEnabled(GetInstructionType(Format(SalesLine."Document Type"), SalesLine."Document No.")) then begin
                CreateAndSendNotification(SalesHeader.RecordId, AdditionalContextId, '');
                SalesHeader.OnCustomerCreditLimitExceeded;
            end;
    end;

    procedure ServiceHeaderCheck(ServiceHeader: Record "Service Header")
    var
        AdditionalContextId: Guid;
    begin
        if not GuiAllowed then
            exit;

        OnNewCheckRemoveCustomerNotifications(ServiceHeader.RecordId, true);

        if CustCheckCreditLimit.ServiceHeaderShowWarningAndGetCause(ServiceHeader, AdditionalContextId) then
            CreateAndSendNotification(ServiceHeader.RecordId, AdditionalContextId, '');
    end;

    procedure ServiceLineCheck(ServiceLine: Record "Service Line")
    var
        ServiceHeader: Record "Service Header";
        AdditionalContextId: Guid;
    begin
        if not GuiAllowed then
            exit;

        if not ServiceHeader.Get(ServiceLine."Document Type", ServiceLine."Document No.") then
            ServiceHeader.Init;
        OnNewCheckRemoveCustomerNotifications(ServiceHeader.RecordId, false);

        if CustCheckCreditLimit.ServiceLineShowWarningAndGetCause(ServiceLine, AdditionalContextId) then
            CreateAndSendNotification(ServiceHeader.RecordId, AdditionalContextId, '');
    end;

    procedure ServiceContractHeaderCheck(ServiceContractHeader: Record "Service Contract Header")
    var
        AdditionalContextId: Guid;
    begin
        if not GuiAllowed then
            exit;

        OnNewCheckRemoveCustomerNotifications(ServiceContractHeader.RecordId, true);

        if CustCheckCreditLimit.ServiceContractHeaderShowWarningAndGetCause(ServiceContractHeader, AdditionalContextId) then
            CreateAndSendNotification(ServiceContractHeader.RecordId, AdditionalContextId, '');
    end;

    procedure GetInstructionType(DocumentType: Code[30]; DocumentNumber: Code[20]): Code[50]
    begin
        exit(CopyStr(StrSubstNo('%1 %2 %3', DocumentType, DocumentNumber, InstructionTypeTxt), 1, 50));
    end;

    procedure BlanketSalesOrderToOrderCheck(SalesOrderHeader: Record "Sales Header")
    var
        AdditionalContextId: Guid;
    begin
        if not GuiAllowed then
            exit;

        OnNewCheckRemoveCustomerNotifications(SalesOrderHeader.RecordId, true);

        if CustCheckCreditLimit.SalesHeaderShowWarningAndGetCause(SalesOrderHeader, AdditionalContextId) then
            CreateAndSendNotification(SalesOrderHeader.RecordId, AdditionalContextId, '');
    end;

    procedure ShowNotificationDetails(CreditLimitNotification: Notification)
    var
        CreditLimitNotificationPage: Page "Credit Limit Notification";
    begin
        CreditLimitNotificationPage.SetHeading(CreditLimitNotification.Message);
        CreditLimitNotificationPage.InitializeFromNotificationVar(CreditLimitNotification);
        CreditLimitNotificationPage.RunModal;
    end;

    local procedure CreateAndSendNotification(RecordId: RecordID; AdditionalContextId: Guid; Heading: Text[250])
    var
        NotificationToSend: Notification;
    begin
        if AdditionalContextId = GetBothNotificationsId then begin
            CreateAndSendNotification(RecordId, GetCreditLimitNotificationId, CustCheckCreditLimit.GetHeading);
            CreateAndSendNotification(RecordId, GetOverdueBalanceNotificationId, CustCheckCreditLimit.GetSecondHeading);
            exit;
        end;

        if Heading = '' then
            Heading := CustCheckCreditLimit.GetHeading;

        case Heading of
            CreditLimitNotificationMsg:
                NotificationToSend.Id(GetCreditLimitNotificationId);
            OverdueBalanceNotificationMsg:
                NotificationToSend.Id(GetOverdueBalanceNotificationId);
            else
                NotificationToSend.Id(CreateGuid);
        end;

        NotificationToSend.Message(Heading);
        NotificationToSend.Scope(NOTIFICATIONSCOPE::LocalScope);
        NotificationToSend.AddAction(GetDetailsTxt, CODEUNIT::"Cust-Check Cr. Limit", 'ShowNotificationDetails');
        CustCheckCreditLimit.PopulateDataOnNotification(NotificationToSend);
        NotificationLifecycleMgt.SendNotificationWithAdditionalContext(NotificationToSend, RecordId, AdditionalContextId);
    end;

    procedure GetCreditLimitNotificationId(): Guid
    begin
        exit('C80FEEDA-802C-4879-B826-34A10FB77087');
    end;

    procedure GetOverdueBalanceNotificationId(): Guid
    begin
        exit('EC8348CB-07C1-499A-9B70-B3B081A33C99');
    end;

    procedure GetBothNotificationsId(): Guid
    begin
        exit('EC8348CB-07C1-499A-9B70-B3B081A33D00');
    end;

    procedure IsCreditLimitNotificationEnabled(Customer: Record Customer): Boolean
    var
        MyNotifications: Record "My Notifications";
    begin
        exit(MyNotifications.IsEnabledForRecord(GetCreditLimitNotificationId, Customer));
    end;

    procedure IsOverdueBalanceNotificationEnabled(Customer: Record Customer): Boolean
    var
        MyNotifications: Record "My Notifications";
    begin
        exit(MyNotifications.IsEnabledForRecord(GetOverdueBalanceNotificationId, Customer));
    end;

    [EventSubscriber(ObjectType::Page, 1518, 'OnInitializingNotificationWithDefaultState', '', false, false)]
    local procedure OnInitializingNotificationWithDefaultState()
    var
        MyNotifications: Record "My Notifications";
    begin
        MyNotifications.InsertDefaultWithTableNum(GetCreditLimitNotificationId,
          CreditLimitNotificationMsg,
          CreditLimitNotificationDescriptionTxt,
          DATABASE::Customer);
        MyNotifications.InsertDefaultWithTableNum(GetOverdueBalanceNotificationId,
          OverdueBalanceNotificationMsg,
          OverdueBalanceNotificationDescriptionTxt,
          DATABASE::Customer);
    end;

    [Scope('Internal')]
    procedure "+++FNK_INHAUS+++"()
    begin
    end;

    [Scope('Internal')]
    procedure fnk_CreditLimitExceeded(par_co_SalesHdrNo: Code[20]; par_te_Company: Text[30])
    var
        lo_re_Cust: Record Customer;
        lo_re_SalesHdr: Record "Sales Header";
        lo_re_SalesHdrView: Record VIEW_SalesHeader;
    begin
        // *** Wenn Kreditlimit überschritten wurde   //B43°.1
        //     - Auftrag öffnen + Kreditlimit setzen
        //     - Fehlermeldung ausgeben
        // ***

        if par_te_Company = CompanyName then begin
            lo_re_SalesHdr.Get(lo_re_SalesHdr."Document Type"::Order, par_co_SalesHdrNo);
            lo_re_SalesHdr."Kreditlimit überschritten" := true;
            lo_re_SalesHdr.Modify(false);
            if lo_re_Cust.Get(lo_re_SalesHdr."Bill-to Customer No.") then;
            //Reopen?
        end else begin
            lo_re_SalesHdr.ChangeCompany(par_te_Company);
            lo_re_SalesHdr.Get(lo_re_SalesHdr."Document Type"::Order, par_co_SalesHdrNo);
            lo_re_SalesHdr."Kreditlimit überschritten" := true;
            lo_re_SalesHdr.Modify(false);

            if lo_re_SalesHdrView.Get(par_te_Company, lo_re_SalesHdrView."Document Type"::Order, par_co_SalesHdrNo) then begin
                if lo_re_Cust.Get(lo_re_SalesHdrView."Bill-to Customer No.") then;
            end;

            //Reopen?
        end;

        Commit;
        if lo_re_Cust.fnk_UsesCompGrpCreditLimit then begin
            Error(TextCreditLimitExceeded, lo_re_Cust.FieldCaption("Company Group") + ' ' + lo_re_Cust."Company Group");
        end else begin
            Error(TextCreditLimitExceeded, lo_re_Cust."No.");
        end;
    end;

    [Scope('Internal')]
    procedure fnk_GetOutstOrd4CrLimitFilter() rv_te_Filter: Text[250]
    var
        lo_cu_LogisticsMgt: Codeunit LogisticsMgt;
    begin
        //B43°.3
        //rv_te_Filter := STRSUBSTNO('..%1',CALCDATE('<+1D>',WORKDATE));
        rv_te_Filter := StrSubstNo('..%1', lo_cu_LogisticsMgt.fnk_GetNextWorkingDay(WorkDate, 0, false));
    end;

    [IntegrationEvent(false, false)]
    procedure OnNewCheckRemoveCustomerNotifications(RecId: RecordID; RecallCreditOverdueNotif: Boolean)
    begin
    end;

    procedure GetCreditLimitNotificationMsg(): Text
    begin
        exit(CreditLimitNotificationMsg);
    end;

    procedure GetOverdueBalanceNotificationMsg(): Text
    begin
        exit(OverdueBalanceNotificationMsg);
    end;
}

